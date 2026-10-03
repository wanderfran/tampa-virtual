#!/bin/bash
# Remove a tampa-virtual (ex.: depois de trocar o sensor da tampa).
#   curl -fsSL https://raw.githubusercontent.com/wanderfran/tampa-virtual/main/desinstalar.sh | bash
ROTULO="com.fr4.tampa-virtual"
launchctl bootout "gui/$(id -u)/$ROTULO" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$ROTULO.plist" "$HOME/.local/bin/tampa-virtual"
echo "Tampa virtual removida."
