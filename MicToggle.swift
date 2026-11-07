import Cocoa
import Carbon
import CoreAudio

// Hardware-style mic mute on F18 (F5 mic/dictation key is remapped to F18 via --apply-keymap).
// Mutes the default input device with its CoreAudio mute flag; devices without one fall back
// to input volume 0. State is always read from the device, so changes made elsewhere show up.

// MARK: - CoreAudio

let systemObject = AudioObjectID(kAudioObjectSystemObject)
let savedVolumeKey = "MicToggleSavedVolumeScalar"

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
let defaultInputAddress = address(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)
let muteAddress = address(kAudioDevicePropertyMute)
let volumeAddress = address(kAudioDevicePropertyVolumeScalar)

func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) -> T? {
    var addr = addr, value = initial, size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
}

func set<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) -> Bool {
    var addr = addr, value = value
    return AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
}

func isSettable(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
    var addr = addr, writable: DarwinBoolean = false
    return AudioObjectHasProperty(object, &addr)
        && AudioObjectIsPropertySettable(object, &addr, &writable) == noErr && writable.boolValue
}

func defaultInput() -> AudioObjectID? {
    guard let id = get(systemObject, defaultInputAddress, AudioObjectID(kAudioObjectUnknown)),
          id != kAudioObjectUnknown else { return nil }
    return id
}

func deviceName(_ device: AudioObjectID) -> String? {
    var addr = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr else { return nil }
    return name?.takeRetainedValue() as String?
}

func canMute(_ d: AudioObjectID) -> Bool { isSettable(d, muteAddress) }
func canSetVolume(_ d: AudioObjectID) -> Bool { isSettable(d, volumeAddress) }

enum MicState { case live, muted, unsupported }

func state(of device: AudioObjectID?) -> MicState {
    guard let d = device, canMute(d) || canSetVolume(d) else { return .unsupported }
    if canMute(d), get(d, muteAddress, UInt32(0)) == 1 { return .muted }
    if canSetVolume(d), get(d, volumeAddress, Float32(1)) == 0 { return .muted }
    return .live
}

/// Returns true only if the device actually ended up in the requested state: some devices
/// accept a write without error and then ignore it.
func setMuted(_ d: AudioObjectID, _ mute: Bool) -> Bool {
    guard canMute(d) || canSetVolume(d) else { return false }
    if mute {
        if canMute(d) {
            _ = set(d, muteAddress, UInt32(1))
        } else {
            if let v = get(d, volumeAddress, Float32(0)), v > 0 { UserDefaults.standard.set(v, forKey: savedVolumeKey) }
            _ = set(d, volumeAddress, Float32(0))
        }
    } else {
        if canMute(d) { _ = set(d, muteAddress, UInt32(0)) }
        // Volume 0 also counts as muted (fallback devices, or left over from the old soft mute): restore it.
        if canSetVolume(d), get(d, volumeAddress, Float32(1)) == 0 {
            let saved = UserDefaults.standard.float(forKey: savedVolumeKey)
            _ = set(d, volumeAddress, saved > 0 ? saved : 0.75)
        }
    }
    return state(of: d) == (mute ? .muted : .live)
}

// MARK: - Key remap (F5 mic key -> F18), merged with any other hidutil mappings

struct KeyMapping: Equatable { let src: UInt64, dst: UInt64 }
let micKeyMapping = KeyMapping(src: 0xC000000CF, dst: 0x70000006D)

func hidutil(_ args: [String]) -> (status: Int32, output: String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = args
    p.standardOutput = pipe
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func parseNumber(_ s: Substring) -> UInt64? {
    s.hasPrefix("0x") ? UInt64(s.dropFirst(2), radix: 16) : UInt64(s)
}

/// All distinct mappings currently set on any keyboard service, or nil if hidutil failed.
func currentKeyMappings() -> [KeyMapping]? {
    let (status, out) = hidutil(["property", "--get", "UserKeyMapping"])
    guard status == 0 else { return nil }
    var result: [KeyMapping] = []
    for block in out.matches(of: #/\{([^{}]*)\}/#) {
        let body = block.output.1
        guard let s = body.firstMatch(of: #/HIDKeyboardModifierMappingSrc\s*=\s*(0x[0-9A-Fa-f]+|\d+)/#),
              let d = body.firstMatch(of: #/HIDKeyboardModifierMappingDst\s*=\s*(0x[0-9A-Fa-f]+|\d+)/#),
              let src = parseNumber(s.output.1), let dst = parseNumber(d.output.1) else { continue }
        let m = KeyMapping(src: src, dst: dst)
        if !result.contains(m) { result.append(m) }
    }
    return result
}

func updateKeymap(install: Bool) -> Int32 {
    guard var mappings = currentKeyMappings() else {
        FileHandle.standardError.write("hidutil --get failed; leaving key mappings unchanged\n".data(using: .utf8)!)
        return 1
    }
    if install {
        mappings.removeAll { $0.src == micKeyMapping.src }
        mappings.append(micKeyMapping)
    } else {
        mappings.removeAll { $0 == micKeyMapping }
    }
    let entries = mappings.map {
        String(format: "{\"HIDKeyboardModifierMappingSrc\":0x%llX,\"HIDKeyboardModifierMappingDst\":0x%llX}", $0.src, $0.dst)
    }
    let json = "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    return hidutil(["property", "--set", json]).status
}

// MARK: - Menu-bar app

final class App: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var mic: AudioObjectID?
    var lastKnownMuted = false
    var lastActionFailed = false
    lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)

        var addr = defaultInputAddress
        AudioObjectAddPropertyListenerBlock(systemObject, &addr, .main) { [weak self] _, _ in
            self?.defaultInputChanged()
        }
        watch(defaultInput())
        refresh()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().toggle(); return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_F18), 0, EventHotKeyID(signature: OSType(0x4D494354), id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    /// Moves the mute/volume listeners to `device`.
    func watch(_ device: AudioObjectID?) {
        for a in [muteAddress, volumeAddress] {
            var a = a
            if let old = mic { AudioObjectRemovePropertyListenerBlock(old, &a, .main, deviceListener) }
            if let new = device { AudioObjectAddPropertyListenerBlock(new, &a, .main, deviceListener) }
        }
        mic = device
    }

    /// Like a laptop's mute key: if muted when the default mic changes, the new mic starts muted too.
    func defaultInputChanged() {
        let new = defaultInput()
        guard new != mic else { return }
        watch(new)
        lastActionFailed = false
        if lastKnownMuted, let new { lastActionFailed = !setMuted(new, true) }
        refresh()
    }

    @objc func toggle() {
        if let d = mic { lastActionFailed = !setMuted(d, state(of: d) != .muted) }
        refresh()
    }

    func refresh() {
        let actual = state(of: mic)
        lastKnownMuted = actual == .muted
        let shown: MicState = lastActionFailed ? .unsupported : actual
        let name = mic.flatMap(deviceName) ?? "No input device"

        let img: NSImage?
        switch shown {
        case .live:
            img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Mic live")
            img?.isTemplate = true
            item.button?.toolTip = "\(name): live (F5 to mute)"
        case .muted:
            img = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Mic muted")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            item.button?.toolTip = "\(name): MUTED (F5 to unmute)"
        case .unsupported:
            img = (NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "Can't mute mic")
                   ?? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Can't mute mic"))?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
            item.button?.toolTip = "Can't mute \(name)"
        }
        item.button?.image = img
    }
}

switch CommandLine.arguments.dropFirst().first {
case "--apply-keymap": exit(updateKeymap(install: true))
case "--remove-keymap": exit(updateKeymap(install: false))
default:
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
