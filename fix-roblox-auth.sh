#!/bin/bash
# Registers the Linux desktop protocol handler for roblox-studio-auth://
# so that clicking "Log in with browser" in Roblox Studio (Wine) correctly
# hands control back from Firefox to Roblox Studio after login.
set -uo pipefail

REPO=/workspaces/literate-octo-fortnight
EXE=$(find "$REPO/.wineprefix/drive_c" -iname "RobloxStudioBeta.exe" 2>/dev/null | head -1)

if [ -z "$EXE" ]; then
  echo "[失敗] RobloxStudioBeta.exe が見つかりません。先にRoblox Studioをインストールしてください。"
  exit 1
fi

mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/roblox-studio-auth.desktop << EOF
[Desktop Entry]
Type=Application
Name=Roblox Studio Auth Handler
Exec=env WINEPREFIX=$REPO/.wineprefix wine "$EXE" %u
MimeType=x-scheme-handler/roblox-studio-auth;
NoDisplay=true
EOF

update-desktop-database ~/.local/share/applications
xdg-mime default roblox-studio-auth.desktop x-scheme-handler/roblox-studio-auth

echo "[完了] roblox-studio-auth:// のハンドラーを登録しました ($EXE)"
