#!/bin/zsh
# Builds MicToggle from source and installs it:
#   - F5 (mic/dictation key) -> F18 remap, re-applied at every login
#   - menu-bar helper that toggles mic mute on F18, started at login and kept alive
set -e
SRC="${0:A:h}"
D="$HOME/Library/Application Support/MicToggle"; LA="$HOME/Library/LaunchAgents"; U=$(id -u)

command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install"; exit 1; }

mkdir -p "$D" "$LA"
swiftc -O "$SRC/MicToggle.swift" -o "$D/MicToggle"

cat > "$LA/com.user.mictoggle.keymap.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.user.mictoggle.keymap</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/hidutil</string><string>property</string><string>--set</string>
    <string>{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0xC000000CF,"HIDKeyboardModifierMappingDst":0x70000006D}]}</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
cat > "$LA/com.user.mictoggle.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.user.mictoggle</string>
  <key>ProgramArguments</key><array><string>$D/MicToggle</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
for f in "$LA/com.user.mictoggle.keymap.plist" "$LA/com.user.mictoggle.plist"; do
  launchctl bootout gui/$U "$f" 2>/dev/null || true
  launchctl bootstrap gui/$U "$f"
done
echo "Installed. Press F5 to toggle mic mute; watch the mic icon in the menu bar."
