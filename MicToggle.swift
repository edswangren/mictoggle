import Cocoa
import Carbon

// Toggles system-wide mic mute (default input volume -> 0 / restore) on F18.
// F5 (mic/dictation key) is remapped to F18 by hidutil (com.user.mictoggle.keymap LaunchAgent).

let savedKey = "MicToggleSavedVolume"

func runAS(_ src: String) -> String? {
    var err: NSDictionary?
    let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
    return r?.stringValue
}
func inputVolume() -> Int { Int(runAS("input volume of (get volume settings)") ?? "") ?? -1 }
func setInputVolume(_ v: Int) { _ = runAS("set volume input volume \(v)") }

final class App: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        refresh()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().toggle(); return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_F18), 0, EventHotKeyID(signature: OSType(0x4D494354), id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    @objc func toggle() {
        let v = inputVolume()
        if v > 0 {
            UserDefaults.standard.set(v, forKey: savedKey)
            setInputVolume(0)
        } else {
            let s = UserDefaults.standard.integer(forKey: savedKey)
            setInputVolume(s > 0 ? s : 75)
        }
        refresh()
    }

    func refresh() {
        let muted = inputVolume() == 0
        let img = NSImage(systemSymbolName: muted ? "mic.slash.fill" : "mic.fill",
                          accessibilityDescription: muted ? "Mic muted" : "Mic live")
        img?.isTemplate = !muted
        item.button?.image = muted ? img?.withSymbolConfiguration(.init(paletteColors: [.systemRed])) : img
        item.button?.toolTip = muted ? "Mic MUTED (F5 to unmute)" : "Mic live (F5 to mute)"
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
