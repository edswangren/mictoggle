# mictoggle

System-wide microphone mute toggle for macOS, bound to the **F5 mic/dictation key**, with a menu-bar indicator.

- **F5** toggles mute in every app (Teams, Zoom, browser, etc.).
- **Menu bar:** a mic icon when live, a red slashed mic when muted. Clicking the icon also toggles.
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

1. **Key remap.** The LaunchAgent `com.user.mictoggle.keymap` runs `hidutil` at login to remap the mic key (consumer usage `0xC000000CF`) to F18, which no Mac keyboard has. The remap doesn't survive a reboot, so it is re-applied at every login.
2. **Helper.** The LaunchAgent `com.user.mictoggle` runs `~/Library/Application Support/MicToggle/MicToggle`, a menu-bar-only app built from `MicToggle.swift`.
3. **Hotkey.** The helper catches F18 with Carbon `RegisterEventHotKey`, so no Accessibility permission is needed.
4. **Mute.** Mute sets the default input device's volume to 0. Unmute restores the previous level, saved in `~/Library/Preferences/MicToggle.plist` (falls back to 75).

## Notes

- This is a "soft" mute: the input level drops to 0, so apps receive silence. A meeting app's own mute button won't change.
- Mute applies to whichever input device was the default when you pressed F5. If you switch mics mid-call, press F5 again if needed. The icon updates every 2 seconds.
- Dictation from the F5 key is disabled while installed. It's still available from Edit → Start Dictation.
- Built and tested on Apple Silicon MacBooks with the built-in keyboard. External keyboards whose mic key sends a different code won't trigger it.
