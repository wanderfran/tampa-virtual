#!/bin/bash
# Instala a tampa-virtual e liga junto com o Mac.
# Uso num Mac zerado:
#   curl -fsSL https://raw.githubusercontent.com/wanderfran/tampa-virtual/main/instalar.sh | bash
set -euo pipefail

RAW="https://raw.githubusercontent.com/wanderfran/tampa-virtual/main"
BIN="$HOME/.local/bin/tampa-virtual"
ROTULO="com.fr4.tampa-virtual"
PLIST="$HOME/Library/LaunchAgents/$ROTULO.plist"
LOG="$HOME/Library/Logs/tampa-virtual.log"

[ "$(uname -m)" = "arm64" ] || { echo "Só funciona em Mac com chip Apple (M1 ou mais novo)."; exit 1; }

mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")" "$(dirname "$LOG")"
curl -fsSL "$RAW/tampa-virtual" -o "$BIN"
chmod +x "$BIN"
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ROTULO</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$ROTULO" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 2
if launchctl print "gui/$(id -u)/$ROTULO" | grep -q "state = running"; then
  echo "Pronto. A tampa virtual está ligada e vai iniciar junto com o Mac."
  echo "Registro: $LOG"
else
  echo "Instalou, mas não ficou rodando. Veja o registro: $LOG"; exit 1
fi
