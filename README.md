# mictoggle

System-wide microphone mute toggle for macOS, bound to the **F5 mic/dictation key**, with a menu-bar indicator.

- **F5** toggles mute in every app (Teams, Zoom, browser, etc.).
- **Menu bar:** a mic icon when live, a red slashed mic when muted, an orange mic with an ✕ when the mic can't be muted. Clicking the icon also toggles.
- Starts at login and is restarted automatically if it quits.

## Install

Requires the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/edswangren/mictoggle.git ~/repos/mictoggle
~/repos/mictoggle/install.sh
```

Re-run `install.sh` after pulling changes to rebuild and restart.

## Uninstall

```sh
~/repos/mictoggle/uninstall.sh
```

This also restores F5 to dictation.

## How it works

1. **Key remap.** The LaunchAgent `com.user.mictoggle.keymap` runs `MicToggle --apply-keymap` at login. It remaps the mic key (consumer usage `0xC000000CF`) to F18, which no Mac keyboard has, using `hidutil`. Any other `hidutil` remaps you have are kept, and uninstall removes only this one. The remap doesn't survive a reboot, so it is re-applied at every login.
2. **Helper.** The LaunchAgent `com.user.mictoggle` runs `~/Library/Application Support/MicToggle/MicToggle`, a menu-bar-only app built from `MicToggle.swift`.
3. **Hotkey.** The helper catches F18 with Carbon `RegisterEventHotKey`, so no Accessibility permission is needed.
4. **Mute.** Mute sets the default input device's own CoreAudio mute flag, the same one a hardware mute switch uses. Every app receives silence, and the input volume isn't touched. A device with no mute flag falls back to input volume 0. Unmuting then restores the previous level, saved in `~/Library/Preferences/MicToggle.plist`, or 75% if none was saved.
5. **State.** The icon reads the device directly and updates the instant anything changes it. That includes Sound settings, another app, or a headset's mute button.

## Notes

- **Unmuting elsewhere sticks.** If another app or Sound settings unmutes the mic, the icon turns live and MicToggle leaves it alone.
- **Switching mics keeps you muted.** If you're muted when the default input changes (e.g. AirPods connect), the new mic is muted too.
- **Some mics can't be muted.** If a mic has neither a mute flag nor an adjustable volume, or the device rejects or ignores the change, the icon becomes an orange mic with an ✕. Hover over it to see the device name.
- **Meeting apps have their own mute.** A meeting app's mute button is separate and won't change. Apps still have the mic open while you're muted, so the orange "mic in use" dot stays on.
- **Device-specific remaps become global.** A remap that another tool limited to one keyboard with `hidutil --matching` applies to all keyboards after `install.sh` or `uninstall.sh` merges the list.
- Dictation from the F5 key is disabled while installed. It's still available from Edit → Start Dictation.
- Built and tested on Apple Silicon MacBooks with the built-in keyboard. External keyboards whose mic key sends a different code won't trigger it.
