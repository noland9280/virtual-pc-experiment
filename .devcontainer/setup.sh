#!/bin/bash
# Runs automatically every time the Codespace/devcontainer is (re)created.
# Kept as a standalone script (instead of a giant one-line JSON string) so it
# can be edited safely without risking JSON-escaping bugs that have broken
# devcontainer.json before.
set -uo pipefail

REPO=/workspaces/literate-octo-fortnight
PERSIST="$REPO/.desktop-persist"

echo "==> Fixing fakeroot (this container doesn't support SysV semaphores properly,"
echo "    which was silently breaking apt installs via dpkg's fakeroot maintainer scripts)"
if update-alternatives --list fakeroot 2>/dev/null | grep -q fakeroot-tcp; then
  sudo update-alternatives --set fakeroot /usr/bin/fakeroot-tcp || true
fi

echo "==> Installing packages"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  language-pack-ja language-pack-gnome-ja language-pack-kde-ja fonts-noto-cjk \
  fcitx5 fcitx5-mozc fcitx5-config-qt fcitx5-frontend-qt5 fcitx5-frontend-gtk3 im-config \
  ffmpeg pulseaudio-utils dbus-x11
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends winehq-stable

echo "==> Japanese locale"
sudo locale-gen ja_JP.UTF-8
sudo update-locale LANG=ja_JP.UTF-8
im-config -n fcitx5
sudo sed -i 's/^LANGUAGE=.*/LANGUAGE="ja_JP:ja"/' /etc/environment

mkdir -p ~/.config/autostart ~/.config/plasma-workspace/env

echo "==> fcitx5 autostart"
cat > ~/.config/autostart/fcitx5.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=fcitx5
Hidden=false
X-GNOME-Autostart-enabled=true
Name=fcitx5
EOF

echo "==> Session D-Bus (fixes fcitx5 'Failed to get reply')"
cat > ~/.config/plasma-workspace/env/00-dbus.sh << 'EOF'
#!/bin/sh
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  eval $(dbus-launch --sh-syntax --exit-with-session)
  export DBUS_SESSION_BUS_ADDRESS
fi
EOF
chmod +x ~/.config/plasma-workspace/env/00-dbus.sh

echo "==> Session-wide locale env"
cat > ~/.config/plasma-workspace/env/01-locale.sh << 'EOF'
#!/bin/sh
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8
export LANGUAGE=ja_JP:ja
EOF
chmod +x ~/.config/plasma-workspace/env/01-locale.sh

echo "==> Persisting desktop customization (wallpapers, icons, cursor themes)"
# These normally live under ~/.local/share and ~/.config, which are OUTSIDE
# /workspaces and get wiped on every rebuild. Symlinking them into a folder
# inside /workspaces means anything you install/change here (wallpapers,
# icon themes, cursor themes, and the settings that select them) survives
# rebuilds automatically. Existing content is migrated on first run only.
mkdir -p "$PERSIST/wallpapers" "$PERSIST/icons" "$PERSIST/plasma-desktoptheme" "$PERSIST/config" "$PERSIST/firefox"

persist_dir() {
  local live="$1" store="$2"
  if [ -L "$live" ]; then return 0; fi
  mkdir -p "$(dirname "$live")"
  if [ -d "$live" ] && [ "$(ls -A "$live" 2>/dev/null)" ]; then
    cp -rn "$live"/. "$store"/ 2>/dev/null || true
    rm -rf "$live"
  fi
  ln -s "$store" "$live"
}

persist_file() {
  local live="$1" store="$2"
  if [ -L "$live" ]; then return 0; fi
  mkdir -p "$(dirname "$live")" "$(dirname "$store")"
  if [ -f "$live" ] && [ ! -e "$store" ]; then
    cp "$live" "$store"
  fi
  touch "$store"
  ln -sf "$store" "$live"
}

persist_dir ~/.local/share/wallpapers "$PERSIST/wallpapers"
persist_dir ~/.local/share/icons "$PERSIST/icons"
persist_dir ~/.local/share/plasma/desktoptheme "$PERSIST/plasma-desktoptheme"
# Firefox's profile (cookies, saved logins/sessions - e.g. ProtonMail webmail,
# Roblox account login) lives under ~/.mozilla, which is OUTSIDE /workspaces
# and gets wiped on every rebuild, forcing a fresh login every time.
# Symlinking it in fixes that the same way as the other persisted dirs.
persist_dir ~/.mozilla/firefox "$PERSIST/firefox"
# Desktop icons (e.g. Roblox Studio shortcut created by its Wine installer)
# and the app-launcher entries Wine registers into the KDE app menu.
persist_dir ~/Desktop "$PERSIST/Desktop"
persist_dir ~/.local/share/applications "$PERSIST/applications"
# These files hold *which* wallpaper/icon/cursor theme is currently selected
persist_file ~/.config/plasma-org.kde.plasma.desktop-appletsrc "$PERSIST/config/plasma-org.kde.plasma.desktop-appletsrc"
persist_file ~/.config/kdeglobals "$PERSIST/config/kdeglobals"
persist_file ~/.config/kcminputrc "$PERSIST/config/kcminputrc"
# Holds the roblox-studio-auth:// -> RobloxStudioBeta.exe association set by
# fix-roblox-auth.sh. Persisting this means that association survives
# rebuilds too, without needing to re-run fix-roblox-auth.sh every time.
persist_file ~/.config/mimeapps.list "$PERSIST/config/mimeapps.list"

echo "==> Roblox Studio desktop shortcut (regenerated every rebuild)"
# Wine's own desktop-integration (winemenubuilder) writes its shortcut into
# the real ~/Desktop, which lives OUTSIDE /workspaces and is wiped on every
# rebuild. Instead of relying on that, we generate the .desktop entry
# ourselves straight into $PERSIST/Desktop (already symlinked from
# ~/Desktop above), pointing at the .exe inside WINEPREFIX, which DOES live
# under /workspaces and survives rebuilds. As long as Roblox Studio itself
# stays installed in the wineprefix, this shortcut comes back every rebuild
# even if it's never been installed in this particular container instance yet.
ROBLOX_EXE=$(find "$REPO/.wineprefix/drive_c" -iname "RobloxStudioBeta.exe" 2>/dev/null | head -1)
if [ -n "$ROBLOX_EXE" ]; then
  cat > "$PERSIST/Desktop/RobloxStudio.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Roblox Studio
Comment=Roblox Studio (Wine)
Exec=env WINEPREFIX=$REPO/.wineprefix wine "$ROBLOX_EXE"
Icon=wine
Terminal=false
Categories=Game;
EOF
  chmod +x "$PERSIST/Desktop/RobloxStudio.desktop"
  echo "    -> ショートカット作成: $ROBLOX_EXE"
else
  echo "    -> RobloxStudioBeta.exe が見つかりません(未インストール、または初回インストール後の次回rebuildから有効になります)"
fi

echo "==> Setting up one-command / one-click service starter"
chmod +x "$REPO/start-services.sh"
# Short alias: just type "startaudio" in any terminal (VS Code or Konsole)
if ! grep -q "alias startaudio=" ~/.bashrc 2>/dev/null; then
  echo "alias startaudio='bash $REPO/start-services.sh'" >> ~/.bashrc
fi
# Clickable desktop icon (a real "button") that opens a terminal and runs it
mkdir -p "$PERSIST/Desktop"
cat > "$PERSIST/Desktop/start-services.desktop" << EOF
[Desktop Entry]
Type=Application
Name=サービス再起動(音声など)
Comment=止まっている音声配信などをまとめて起動します
Exec=konsole --noclose -e bash $REPO/start-services.sh
Icon=media-playback-start
Terminal=false
EOF
chmod +x "$PERSIST/Desktop/start-services.desktop"

echo "==> Restarting desktop session to apply everything"
sudo supervisorctl restart all || true

echo "==> postCreateCommand finished"
