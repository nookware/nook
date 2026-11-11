#!/usr/bin/env bash
# Undo Nook: restore the settings saved by the first apply.sh run and remove our files.
# usage: uninstall.sh [backup-dir]   (default: the oldest backup, i.e. your pre-Nook setup)
set -euo pipefail
source "$(dirname "$0")/../lib/lib.sh"

src=${1:-$(ls -d "$NOOK_STATE"/backup-* 2>/dev/null | sort | head -1 || true)}
[ -n "$src" ] && [ -d "$src" ] || die "no backup found in ${NOOK_STATE/#$HOME/\~}"
step "restoring from ${src/#$HOME/\~}"

python3 "$REPO/plasma/shortcuts.py" unbind "$REPO/config/shortcuts.conf" || true

# kwinrulesrc / breezerc / btop.conf etc. that did not exist before get removed, the rest restored.
for f in kdeglobals kwinrc kwinrulesrc plasmarc konsolerc kscreenlockerrc plasmashellrc \
         fastfetch/config.jsonc cava/config btop/btop.conf; do
  rel=".config/$f"
  if [ -e "$src/$rel" ]; then cp -a "$src/$rel" "$HOME/$rel"
  else rm -f "$HOME/$rel"; fi
done
# bat's and ripgrep's configs came later, so older backups lack them: take the oldest copy that
# isn't ours (those start with a Nook comment), or remove ours if there is none.
for f in bat/config ripgrep/config; do
  rel=".config/$f" orig=""
  for b in "$src" $(ls -d "$NOOK_STATE"/backup-* 2>/dev/null | sort); do
    [ -e "$b/$rel" ] && ! head -1 "$b/$rel" | grep -q Nook && { orig="$b/$rel"; break; }
  done
  if [ -n "$orig" ]; then cp -a "$orig" "$HOME/$rel"
  elif head -1 "$HOME/$rel" 2>/dev/null | grep -q Nook; then rm -f "$HOME/$rel"; fi
done
[ -e "$src/.bashrc" ] && cp -a "$src/.bashrc" "$HOME/.bashrc" || sed -i '/# nook$/d' "$HOME/.bashrc"
[ -e "$src/.zshrc" ] && cp -a "$src/.zshrc" "$HOME/.zshrc" || sed -i '/# nook$/d' "$HOME/.zshrc" 2>/dev/null
rm -f "$HOME/.oh-my-zsh/custom/themes/nook.zsh-theme" "$XDG_DATA_HOME/nook/zshrc" \
      "$XDG_DATA_HOME/nook/tools.sh" "$XDG_CONFIG_HOME/bat/themes/Nook.tmTheme"
for inc in gitconfig delta.gitconfig; do
  git config --global --fixed-value --unset-all include.path "$XDG_DATA_HOME/nook/$inc" 2>/dev/null || true
  rm -f "$XDG_DATA_HOME/nook/$inc"
done
batbin=$(command -v bat || command -v batcat || true)
[ -n "$batbin" ] && "$batbin" cache --build >/dev/null 2>&1 || true
rm -rf "$XDG_DATA_HOME/nook/brave-theme"  # Brave keeps working; remove the theme in brave://extensions
if [ -f "$NOOK_STATE/omz-installed-by-nook" ]; then
  rm -rf "$HOME/.oh-my-zsh" "$NOOK_STATE/omz-installed-by-nook"
fi

# Zed may have been themed after the first backup, so take the oldest backup that has its settings.
for zd in "$XDG_CONFIG_HOME/zed" "$HOME/.var/app/dev.zed.Zed/config/zed"; do
  [ -e "$zd/themes/nook.json" ] || continue
  rm -f "$zd/themes/nook.json"
  rel=${zd#"$HOME"/}/settings.json
  if grep -qxF "$zd/settings.json" "$NOOK_STATE/zed-created" 2>/dev/null; then
    rm -f "$zd/settings.json"; continue
  fi
  for b in "$src" $(ls -d "$NOOK_STATE"/backup-* 2>/dev/null | sort); do
    [ -e "$b/$rel" ] && { cp -a "$b/$rel" "$HOME/$rel"; break; }
  done
done
rm -f "$NOOK_STATE/zed-created"

pkill -f "nook-tr[a]y" 2>/dev/null || true
# .desktop copies appicons.py made to point an app at a theme icon
{ grep -lx 'X-Nook-Icon=true' "$XDG_DATA_HOME"/applications/*.desktop 2>/dev/null || true; } | xargs -r rm -f
kbuildsycoca6 >/dev/null 2>&1 || true
rm -f "$HOME/.local/bin/nook-keys" "$HOME/.local/bin/nook-tray" "$HOME/.local/bin/nook-brave" \
      "$XDG_CONFIG_HOME/autostart/nook-tray.desktop" "$NOOK_STATE/tray-seen" \
      "$XDG_DATA_HOME/konsole/Nook.profile" "$XDG_DATA_HOME/konsole/Nook.colorscheme" \
      "$XDG_DATA_HOME/icons/hicolor/scalable/apps/nook.svg" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/nook-start.svg" \
      "$XDG_CONFIG_HOME/fastfetch/nook-logo.txt" "$XDG_CONFIG_HOME/fastfetch/candy-logo.txt" "$XDG_CONFIG_HOME/fastfetch/axolotl.jsonc" "$XDG_CONFIG_HOME/fastfetch/axolotl-logo.txt" "$XDG_CONFIG_HOME/alacritty/nook.toml" \
      "$XDG_DATA_HOME/kxmlgui5/konsole/konsoleui.rc" "$XDG_DATA_HOME/kxmlgui5/konsole/sessionui.rc" "$XDG_CONFIG_HOME/btop/themes/nook.theme"

# shellcheck disable=SC1091
source "$src/previous.env"
[ -n "${colorscheme:-}" ] && plasma-apply-colorscheme "$colorscheme" >/dev/null 2>&1 || true
[ -n "${desktoptheme:-}" ] && plasma-apply-desktoptheme "$desktoptheme" >/dev/null 2>&1 || true
if [ -n "${lookandfeel:-}" ] && [ "$lookandfeel" != org.nook.desktop ]; then
  kwrite --file kdeglobals --group KDE --key LookAndFeelPackage "$lookandfeel"
else kwrite --file kdeglobals --group KDE --key LookAndFeelPackage --delete; fi
changeicons=$(ls /usr/libexec/plasma-changeicons /usr/lib/*/libexec/plasma-changeicons 2>/dev/null | head -1 || true)
[ -n "${icons:-}" ] && [ -n "$changeicons" ] && "$changeicons" "$icons" >/dev/null 2>&1 || true
# the cursor: the oldest backup that recorded one from before Nook's
cursor="" cursorsize=""
for b in $(ls -d "$NOOK_STATE"/backup-* 2>/dev/null | sort); do
  c=$(sed -n 's/^cursor=//p' "$b/previous.env" 2>/dev/null)
  [ -n "$c" ] && [ "$c" != Nook-Cursors ] && { cursor=$c; cursorsize=$(sed -n 's/^cursorsize=//p' "$b/previous.env"); break; }
done
plasma-apply-cursortheme ${cursorsize:+--size "$cursorsize"} "${cursor:-breeze_cursors}" >/dev/null 2>&1 || true
rm -f "$XDG_DATA_HOME/color-schemes/Nook.colors"
rm -rf "$XDG_DATA_HOME/kwin/scripts/krohnkite" "$XDG_DATA_HOME/kwin/scripts/nook-tiling" "$XDG_DATA_HOME/aurorae/themes/Nook" \
       "$XDG_DATA_HOME/plasma/desktoptheme/nook" "$XDG_DATA_HOME/icons/Nook" \
       "$XDG_DATA_HOME"/plasma/plasmoids/org.nook.{apps,clock,sys} "$XDG_DATA_HOME/plasma/look-and-feel/org.nook.desktop" \
       "$XDG_DATA_HOME/icons/Nook-Breeze" "$XDG_DATA_HOME/icons/Nook-Cursors"
gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null 2>&1 || true

# the login screen is system-wide, so this part asks for sudo
{ [ -e /etc/sddm.conf.d/zz-nook.conf ] || [ -e /usr/share/color-schemes/Nook.colors ]; } && { "$REPO/shared/login/login.sh" --remove || warn "login screen left as it is"; }

# The panel layout lives in plasmashell's own config: restart it to load the restored file.
kquitapp6 plasmashell >/dev/null 2>&1 || true
sleep 2
if [ -e "$src/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
  cp -a "$src/.config/plasma-org.kde.plasma.desktop-appletsrc" "$XDG_CONFIG_HOME/"
fi
(setsid -f plasmashell >/dev/null 2>&1 &)
ok "restored. Log out and back in to reset fonts in running apps."
