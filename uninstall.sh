#!/bin/zsh
# Removes MicToggle and restores F5 to dictation. Other hidutil key remaps are left alone.
D="$HOME/Library/Application Support/MicToggle"; LA="$HOME/Library/LaunchAgents"; U=$(id -u)
for f in "$LA/com.user.mictoggle.plist" "$LA/com.user.mictoggle.keymap.plist"; do
  launchctl bootout gui/$U "$f" 2>/dev/null; rm -f "$f"
done
if [[ -x "$D/MicToggle" ]]; then
  "$D/MicToggle" --remove-keymap || echo "Warning: couldn't remove the F5 remap; it will be gone after the next reboot."
fi
rm -rf "$D"
defaults delete MicToggle 2>/dev/null
echo "MicToggle removed (F5 is dictation again)."
