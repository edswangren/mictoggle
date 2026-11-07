#!/bin/zsh
# Removes MicToggle and restores F5 to dictation.
LA="$HOME/Library/LaunchAgents"; U=$(id -u)
for f in "$LA/com.user.mictoggle.plist" "$LA/com.user.mictoggle.keymap.plist"; do
  launchctl bootout gui/$U "$f" 2>/dev/null; rm -f "$f"
done
hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
rm -rf "$HOME/Library/Application Support/MicToggle"
defaults delete MicToggle 2>/dev/null
echo "MicToggle removed (F5 is dictation again)."
