#!/usr/bin/env bash
# Apply Nook to the current user's Plasma 6 session. No sudo needed.
# Everything it overwrites is copied to ~/.local/state/nook/backup-<time>/ first;
# uninstall.sh puts the oldest backup (your pre-Nook setup) back.
#
# usage: apply.sh [--palette=cocoa|ramen] [--no-panel] [--no-shell] [--no-shortcuts] [--no-icons] [--no-cursor] [--no-widgets]
#   --palette=cocoa|ramen  (or --cocoa / --ramen) the colours for everything: colour scheme, Plasma
#             style, window frames, wallpaper, widgets, icons, cursor, terminal and CLI themes.
#             cocoa = the warm pastels, ramen = Ramen Sign (neutral greys, neons). Remembered.
set -euo pipefail
source "$(dirname "$0")/../lib/lib.sh"

DO_PANEL=1 DO_KEYS=1 DO_ICONS=1 DO_CURSOR=1 DO_WIDGETS=1
PALETTE=$(cat "$NOOK_STATE/palette" 2>/dev/null || echo cocoa)
[ "$PALETTE" = pastel ] && PALETTE=cocoa
for a in "$@"; do
  case "$a" in
    --ramen) PALETTE=ramen ;; --pastel|--cocoa) PALETTE=cocoa ;;
    --palette=*) PALETTE=${a#--palette=} ;;
    --no-panel) DO_PANEL=0 ;; --no-shell) ;;   # the shell is its own part now (./nook)
    --no-shortcuts) DO_KEYS=0 ;; --no-icons) DO_ICONS=0 ;; --no-cursor) DO_CURSOR=0 ;;
    --no-widgets) DO_WIDGETS=0 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option $a" ;;
  esac
done

have kwriteconfig6 || die "this needs KDE Plasma 6 (kwriteconfig6 not found)"
pgrep -x plasmashell >/dev/null || die "plasmashell is not running; log into a Plasma session first"

CFG=$XDG_CONFIG_HOME
BIN="$HOME/.local/bin"
# the palette every generator below reads (icons.py, themegen.py, wallpaper.py, appicons.py)
export NOOK_PALETTE=$PALETTE
mkdir -p "$NOOK_STATE"; echo "$PALETTE" > "$NOOK_STATE/palette"
if [ "$PALETTE" = ramen ]; then SCHEME=NookRamen ICONS=Nook-Ramen; else SCHEME=Nook ICONS=Nook; fi
[ -f "$REPO/palettes/$PALETTE.json" ] || die "unknown palette $PALETTE (have: $(ls "$REPO/palettes" | sed 's/\.json//' | tr '\n' ' '))"
# files with the palette written into them (drawn in cocoa) are recoloured where they're installed
ramenize() { [ "$PALETTE" = cocoa ] && return 0; python3 -I "$REPO/lib/recolor.py" --from cocoa --to "$PALETTE" "$@" >/dev/null; }
FONT=$(mono_font)
ZSHBIN=$(command -v zsh || true)
SCREENS=$(screens)
[ -n "$SCREENS" ] || die "could not read the screen layout from plasmashell"
# installs from before the rename (Hackmachine) and the old hack menu get cleaned up first
source "$REPO/plasma/migrate.sh"
BACKUP_DIR="$NOOK_STATE/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR" "$NOOK_SHARE" "$BIN"

# ── 0 · backup ──────────────────────────────────────────────────────────────
step "backing up current settings → ${BACKUP_DIR/#$HOME/\~}"
backup "$CFG/kdeglobals" "$CFG/kwinrc" "$CFG/kwinrulesrc" "$CFG/plasmarc" \
       "$CFG/konsolerc" "$CFG/kscreenlockerrc" "$CFG/plasma-org.kde.plasma.desktop-appletsrc" \
       "$CFG/plasmashellrc" "$CFG/kglobalshortcutsrc" "$CFG/fastfetch/config.jsonc" \
       "$CFG/cava/config" "$CFG/btop/btop.conf" "$HOME/.bashrc" \
       "$CFG/kcminputrc" "$CFG/bat/config" "$CFG/ripgrep/config"
# Names the uninstaller re-applies through Plasma's own tools.
{
  printf 'colorscheme=%q\n' "$(kread --file kdeglobals --group General --key ColorScheme)"
  printf 'icons=%q\n' "$(kread --file kdeglobals --group Icons --key Theme)"
  printf 'desktoptheme=%q\n' "$(kread --file plasmarc --group Theme --key name)"
  printf 'cursor=%q\n' "$(kread --file kcminputrc --group Mouse --key cursorTheme)"
  printf 'cursorsize=%q\n' "$(kread --file kcminputrc --group Mouse --key cursorSize)"
  printf 'lookandfeel=%q\n' "$(kread --file kdeglobals --group KDE --key LookAndFeelPackage)"
} > "$BACKUP_DIR/previous.env"
ok "backup done"

# ── 1 · files ───────────────────────────────────────────────────────────────
step "installing theme files"
install -Dm644 "$REPO/palettes/kde/Nook.colors" "$XDG_DATA_HOME/color-schemes/Nook.colors"
install -Dm644 "$REPO/palettes/kde/NookRamen.colors" "$XDG_DATA_HOME/color-schemes/NookRamen.colors"
install -Dm644 "$REPO/plasma/theme/konsole/Nook.colorscheme" "$XDG_DATA_HOME/konsole/Nook.colorscheme"
install -Dm644 "$REPO/shared/icons/svg/nook.svg" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/nook.svg"
install -Dm644 "$REPO/shared/icons/svg/nook-start.svg" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/nook-start.svg"
ramenize "$XDG_DATA_HOME/konsole/Nook.colorscheme" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/nook.svg" \
         "$XDG_DATA_HOME/icons/hicolor/scalable/apps/nook-start.svg"
install -Dm755 "$REPO/plasma/bin/nook-keys" "$BIN/nook-keys"
install -Dm755 "$REPO/plasma/bin/nook-tray" "$BIN/nook-tray"
install -Dm755 "$REPO/plasma/bin/nook-brave" "$BIN/nook-brave"
rm -rf "$NOOK_SHARE/brave-theme"; cp -r "$REPO/plasma/theme/brave/nook" "$NOOK_SHARE/brave-theme"; ramenize "$NOOK_SHARE/brave-theme"
install -Dm644 "$REPO/plasma/shortcuts.py" "$NOOK_SHARE/shortcuts.py"
install -Dm644 "$REPO/config/shortcuts.conf" "$NOOK_SHARE/shortcuts.conf"
gtk-update-icon-cache -q "$XDG_DATA_HOME/icons/hicolor" 2>/dev/null || true
# Nook widgets (the panel clock needs them before the taskbar is built)
for pl in apps clock sys; do
  dst="$XDG_DATA_HOME/plasma/plasmoids/org.nook.$pl"
  rm -rf "$dst"; mkdir -p "$(dirname "$dst")"
  cp -r "$REPO/plasma/theme/plasmoids/org.nook.$pl" "$dst"
  ramenize "$dst"
done

cat > "$XDG_DATA_HOME/konsole/Nook.profile" <<EOF
[Appearance]
ColorScheme=Nook
Font=$FONT,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[Cursor Options]
CursorShape=0

[General]
${ZSHBIN:+Command=$ZSHBIN}
Environment=TERM=xterm-256color,COLORTERM=truecolor,NOOK=1
Name=Nook
Parent=FALLBACK/
TerminalCenter=true
TerminalMargin=12

[Scrolling]
ScrollBarPosition=2
EOF
kwrite --file konsolerc --group "Desktop Entry" --key DefaultProfile Nook.profile
# No toolbars in Konsole: just the window decoration and the terminal. The layout files are compiled
# into Konsole, so fetch the ones for the installed version from KDE and drop their <ToolBar>s.
# (Menus stay reachable: Ctrl+Shift+M or right-click.)
kver=$(konsole --version 2>/dev/null | awk '{print $2}')
if [ -n "$kver" ]; then
  kui="$XDG_DATA_HOME/kxmlgui5/konsole"; mkdir -p "$kui"
  for rc in konsoleui.rc sessionui.rc; do
    if curl -fsSL "https://invent.kde.org/utilities/konsole/-/raw/v$kver/desktop/$rc" -o "$kui/$rc.tmp"; then
      python3 - "$kui/$rc.tmp" <<'NOTOOLBAR'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"\s*<ToolBar\b.*?</ToolBar>", "", s, flags=re.S)
open(p, "w").write(s)
NOTOOLBAR
      mv "$kui/$rc.tmp" "$kui/$rc"
    else
      rm -f "$kui/$rc.tmp"; warn "could not fetch Konsole $kver's $rc; its toolbar stays"
    fi
  done
fi
kwrite --file konsolerc --group KonsoleWindow --key ShowMenuBarByDefault false
ok "konsole profile (the fallback terminal), nook-keys"

# kitty is the default terminal, the same one as in nook-tile; Konsole stays on Ctrl+Alt+T for
# when something breaks. nook-tile links ~/.config/kitty/nook.conf into the repo; when that link
# is there it stays (one terminal look for both sessions), otherwise Plasma's palette gets a copy.
mkdir -p "$CFG/kitty"
if [ -L "$CFG/kitty/nook.conf" ]; then
  ok "kitty: nook-tile's config kept"
else
  install -Dm644 "$REPO/tile/kitty/nook.conf" "$CFG/kitty/nook.conf"
  [ "$PALETTE" = ramen ] || python3 -I "$REPO/lib/recolor.py" --from ramen --to "$PALETTE" "$CFG/kitty/nook.conf" >/dev/null
fi
touch "$CFG/kitty/kitty.conf"
grep -q '^include nook.conf' "$CFG/kitty/kitty.conf" || printf '\ninclude nook.conf\n' >> "$CFG/kitty/kitty.conf"
[ -n "$ZSHBIN" ] && ! grep -q '^shell ' "$CFG/kitty/kitty.conf" && printf 'shell %s\n' "$ZSHBIN" >> "$CFG/kitty/kitty.conf"
kwrite --file kdeglobals --group General --key TerminalApplication kitty
kwrite --file kdeglobals --group General --key TerminalService kitty.desktop
# Alacritty was the terminal before: nook's own config for it goes
if grep -qs "Written by Nook's apply.sh" "$CFG/alacritty/alacritty.toml"; then
  rm -f "$CFG/alacritty/alacritty.toml"
fi
rm -f "$CFG/alacritty/nook.toml"; rmdir "$CFG/alacritty" 2>/dev/null || true
ok "kitty is the default terminal (Konsole still on Ctrl+Alt+T)"

# Zed: native (~/.config/zed) and Flatpak (its own config dir) each get the theme + font.
zed_dirs=()
{ [ -d "$CFG/zed" ] || have zed || have zeditor; } && zed_dirs+=("$CFG/zed")
zflat="$HOME/.var/app/dev.zed.Zed/config/zed"
{ [ -d "$zflat" ] || flatpak info dev.zed.Zed >/dev/null 2>&1; } && zed_dirs+=("$zflat")
for zd in "${zed_dirs[@]}"; do
  backup "$zd/settings.json"
  # remember settings files we create, so uninstall deletes them instead of restoring ours
  [ -e "$zd/settings.json" ] || echo "$zd/settings.json" >> "$NOOK_STATE/zed-created"
  install -Dm644 "$REPO/plasma/theme/zed/nook.json" "$zd/themes/nook.json"
  ramenize "$zd/themes/nook.json"
  python3 "$REPO/plasma/zed.py" "$zd/settings.json" "$FONT"
  ok "zed theme Nook + $FONT → ${zd/#$HOME/\~}"
done




# ── 2 · colours, plasma style, icons ─────────────────────────────────────────
step "colours + plasma style"
plasma-apply-colorscheme "$SCHEME" >/dev/null 2>&1 || plasma-apply-colorscheme "$SCHEME"
kwrite --file kdeglobals --group KDE --key widgetStyle Breeze
pstyle="$XDG_DATA_HOME/plasma/desktoptheme/nook"
rm -rf "$pstyle"
python3 "$REPO/plasma/themegen.py" plasma "$pstyle"
# Plasma caches theme SVGs; drop the cache so a regenerated style shows up at once.
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/plasma-svgelements* "${XDG_CACHE_HOME:-$HOME/.cache}"/plasma_theme_nook*
plasma-apply-desktoptheme nook >/dev/null 2>&1 || plasma-apply-desktoptheme nook
ok "$SCHEME colours + Plasma style ($PALETTE)"

# The global theme holds the logout / restart / shut-down screen; what it leaves out (splash,
# lock screen) comes from Breeze. Only its name is set: plasma-apply-lookandfeel would also
# reset the panel layout.
lnf="$XDG_DATA_HOME/plasma/look-and-feel/org.nook.desktop"
rm -rf "$lnf"; mkdir -p "$(dirname "$lnf")"
cp -r "$REPO/plasma/theme/look-and-feel/org.nook.desktop" "$lnf"
ramenize "$lnf"
kwrite --file kdeglobals --group KDE --key LookAndFeelPackage org.nook.desktop
ok "global theme Nook (logout screen; preview: /usr/libexec/ksmserver-logout-greeter --windowed)"

if [ "$DO_ICONS" = 1 ]; then
  # BeautyLine + Breeze symbolic, one colour per category, in this palette
  "$REPO/shared/icons/build.sh" "$PALETTE"
  kbuildsycoca6 >/dev/null 2>&1 || true
  changeicons=$(ls /usr/libexec/plasma-changeicons /usr/lib/*/libexec/plasma-changeicons \
                   /usr/lib/libexec/plasma-changeicons 2>/dev/null | head -1 || true)
  if [ -n "$changeicons" ]; then "$changeicons" "$ICONS" >/dev/null 2>&1 || true
  else kwrite --file kdeglobals --group Icons --key Theme "$ICONS"; fi
  # tell running apps (KWin's title bars too) to reload icons now instead of at the next login
  for g in 0 1 2 3 4 5; do
    dbus-send --session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged int32:$g 2>/dev/null || true
  done
  ok "icon theme $ICONS"
fi

if [ "$DO_CURSOR" = 1 ] && [ "$PALETTE" = ramen ]; then
  step "cursor: Nook-Pixel (old-school pixel cursors)"
  python3 -I "$REPO/shared/cursors/pixelcursors.py" "$XDG_DATA_HOME/icons/Nook-Pixel" >/dev/null
  plasma-apply-cursortheme --size 16 Nook-Pixel >/dev/null 2>&1 || {
    kwrite --file kcminputrc --group Mouse --key cursorTheme Nook-Pixel
    kwrite --file kcminputrc --group Mouse --key cursorSize 16
  }
  ok "cursor theme Nook-Pixel"
elif [ "$DO_CURSOR" = 1 ]; then
  step "cursor: Posy's cursors in cocoa and cream"
  # Posy's Cursor (Michiel de Boer; Linux port by simtrami, CC BY-NC 4.0) is fetched at a fixed
  # commit and recoloured locally; it is not vendored here.
  POSY_REV=ffef15950490af620fd0f70cc98847880f63d96e
  posy_src="$NOOK_STATE/src/posy-$POSY_REV"
  if [ ! -d "$posy_src/Posy_Cursor/cursors" ]; then
    mkdir -p "$NOOK_STATE/src"
    tmp=$(mktemp -d "$NOOK_STATE/src/dl.XXXXXX")
    curl -fsSL "https://codeload.github.com/simtrami/posy-improved-cursor-linux/tar.gz/$POSY_REV" \
      | tar -xz -C "$tmp" || die "could not download Posy's cursors"
    rm -rf "$posy_src"; mv "$tmp"/posy-improved-cursor-linux-* "$posy_src" && rmdir "$tmp"
  fi
  python3 "$REPO/plasma/cursors.py" "$posy_src/Posy_Cursor" "$XDG_DATA_HOME/icons/Nook-Cursors" "Nook-Cursors" >/dev/null
  # 32 is Posy's own base size; the theme also carries 48, 64, 96 and 128 for scaled screens
  plasma-apply-cursortheme --size 32 Nook-Cursors >/dev/null 2>&1 || {
    kwrite --file kcminputrc --group Mouse --key cursorTheme Nook-Cursors
    kwrite --file kcminputrc --group Mouse --key cursorSize 32
  }
  ok "cursor theme Nook-Cursors (the login screen gets it from shared/login/login.sh)"
fi

# ── 3 · fonts: monospace everywhere ──────────────────────────────────────────
step "fonts → $FONT"
f() { echo "$FONT,$1,-1,5,$2,0,0,0,0,0,0,0,0,0,0,1"; }
kwrite --file kdeglobals --group General --key font "$(f 10 400)"
kwrite --file kdeglobals --group General --key fixed "$(f 10 400)"
kwrite --file kdeglobals --group General --key menuFont "$(f 10 400)"
kwrite --file kdeglobals --group General --key toolBarFont "$(f 10 400)"
kwrite --file kdeglobals --group General --key smallestReadableFont "$(f 8 400)"
kwriteconfig6 --notify --file kdeglobals --group WM --key activeFont "$(f 10 700)" 2>/dev/null \
  || kwrite --file kdeglobals --group WM --key activeFont "$(f 10 700)"
ok "fonts set"

# ── 4 · windows ─────────────────────────────────────────────────────────────
step "window decoration + rules"
deco="$XDG_DATA_HOME/aurorae/themes/Nook"
rm -rf "$deco"
python3 "$REPO/plasma/themegen.py" aurorae "$deco"
kwrite --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwrite --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__Nook
kwrite --file kwinrc --group org.kde.kdecoration2 --key BorderSize Normal
kwrite --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "M"
kwrite --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight "IAX"
kwrite --file kwinrc --group Plugins --key blurEnabled true

# Tiling: Krohnkite (MIT), a dynamic tiler as a KWin script, fetched at a fixed release.
# Every new window is tiled; dialogs and plasmashell float. Keys: section 7.
KK_REV=0.9.9.2 KK_SHA=42f7f66531d366c74b5fc860381da3517ccb4cdccd1f80c122fcab6e9a8fcf7e
kk_dir="$XDG_DATA_HOME/kwin/scripts/krohnkite"
if ! grep -q "\"Version\": \"$KK_REV\"" "$kk_dir/metadata.json" 2>/dev/null; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/krohnkite.kwinscript" \
    "https://github.com/anametologin/krohnkite/releases/download/$KK_REV/krohnkite-${KK_REV}_1d7fd74.kwinscript" \
    || die "could not download Krohnkite"
  echo "$KK_SHA  $tmp/krohnkite.kwinscript" | sha256sum -c --quiet - || die "Krohnkite checksum mismatch"
  python3 -I -m zipfile -e "$tmp/krohnkite.kwinscript" "$tmp/x"
  rm -rf "$kk_dir"; mv "$tmp/x" "$kk_dir"; rm -rf "$tmp"
fi
# portrait screens start with a top/bottom split instead of side by side
python3 "$REPO/plasma/krohnkite.py" "$kk_dir/contents/code/script.js" || warn "portrait screens keep the side-by-side split"
K=Script-krohnkite
for side in Left Right Top Bottom Between; do
  kwrite --file kwinrc --group $K --key screenGap$side 8
done
kwrite --file kwinrc --group $K --key notificationDuration 600
kwrite --file kwinrc --group Plugins --key krohnkiteEnabled true
# arrow keys that cross to the next screen at the edge, see plasma/theme/kwin/nook-tiling
script_dir="$XDG_DATA_HOME/kwin/scripts/nook-tiling"
rm -rf "$script_dir"; mkdir -p "$(dirname "$script_dir")"
cp -r "$REPO/plasma/theme/kwin/nook-tiling" "$script_dir"
kwrite --file kwinrc --group Plugins --key nook-tilingEnabled true
# Some apps' windows name another app id than their .desktop file (the Discord flatpak says
# "discord"), so the taskbar can't match them to their pin and starts a second copy on click.
# One rule per pinned app gives its windows the right .desktop file; other rules are kept.
rules=$(kread --file kwinrulesrc --group General --key rules | tr ',' '\n' | { grep -v '^nook-app-' || true; })
if [ -f "$CFG/kwinrulesrc" ]; then
  awk '/^\[/ { skip = /^\[nook-app-/ } !skip' "$CFG/kwinrulesrc" > "$CFG/kwinrulesrc.tmp"
  mv "$CFG/kwinrulesrc.tmp" "$CFG/kwinrulesrc"
fi
while IFS=$'\t' read -r wmclass id; do
  [ -n "$id" ] || continue
  g="nook-app-$id"
  kwrite --file kwinrulesrc --group "$g" --key Description "Nook: $wmclass windows belong to $id"
  kwrite --file kwinrulesrc --group "$g" --key wmclass "$wmclass"
  kwrite --file kwinrulesrc --group "$g" --key wmclassmatch 1
  kwrite --file kwinrulesrc --group "$g" --key desktopfile "$id"
  kwrite --file kwinrulesrc --group "$g" --key desktopfilerule 2
  rules+=$'\n'"$g"
done < <(python3 "$REPO/plasma/apps.py" "$REPO/config/apps.conf" wmclass 2>/dev/null)
rules=$(grep . <<<"$rules" | paste -sd, - || true)
kwrite --file kwinrulesrc --group General --key rules "$rules"
kwrite --file kwinrulesrc --group General --key count "$(awk -F, '{print NF}' <<<"$rules")"
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
  || gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null
ok "Nook decoration: lavender focus ring, [_] [□] [x], Krohnkite tiling"

# plasmashell only reads fonts and the icon theme at start-up, so restart it once, before the
# wallpaper, taskbar and widgets go in: it saves widget positions with a delay, and a restart
# right after placing them can lose them.
step "restarting plasmashell"
if systemctl --user is-active -q plasma-plasmashell.service 2>/dev/null; then
  systemctl --user restart plasma-plasmashell.service
else
  kquitapp6 plasmashell >/dev/null 2>&1 || true; sleep 1; (setsid -f plasmashell >/dev/null 2>&1 &)
fi
for _ in $(seq 30); do [ -n "$(screens 2>/dev/null)" ] && break; sleep 1; done
SCREENS=$(screens)
[ -n "$SCREENS" ] || die "plasmashell did not come back after the restart"
ok "plasmashell restarted"

# ── 5 · wallpaper with the key cheat-sheet, one per screen ──────────────────
step "wallpapers"
render() {  # svg png
  if have rsvg-convert; then rsvg-convert -o "$2" "$1"
  elif have inkscape; then inkscape "$1" --export-type=png --export-filename="$2" >/dev/null 2>&1
  elif have magick; then magick -background none "$1" "$2"
  else die "need rsvg-convert, inkscape or imagemagick to render the wallpaper (run ./nook with packages on)"; fi
}
js="" layout_in=""
while read -r id screen x y w h; do
  # the primary screen holds the taskbar, so the banner moves up there
  panel=0; [ "$screen" = 0 ] && panel=44
  png="$NOOK_SHARE/wallpaper-${w}x${h}-p$panel.png"
  # the desktop widgets take the free area, so the skull goes
  skull=""; [ "$DO_WIDGETS" = 1 ] && skull=--no-skull
  python3 "$REPO/plasma/wallpaper.py" "$REPO/config/shortcuts.conf" "${png%.png}.svg" "${w}x$h" "$FONT" "$panel" $skull
  layout_in+="$id $screen $w $h ${png%.png}.json"$'\n'
  render "${png%.png}.svg" "$png"
  js+="d = desktopById($id); d.wallpaperPlugin = 'org.kde.image';
       d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
       d.writeConfig('Image', 'file://$png'); d.writeConfig('FillMode', 2);"
  [ "$screen" = 0 ] && lock_png=$png
  ok "screen $screen: ${w}x$h$([ "$h" -gt "$w" ] && echo ' (portrait)')"
done <<<"$SCREENS"
plasma_eval "var d; $js" >/dev/null
kwrite --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$lock_png"
ok "lock screen uses the primary screen's wallpaper"

# ── 6 · taskbar ─────────────────────────────────────────────────────────────
if [ "$DO_PANEL" = 1 ]; then
  step "taskbar"
  launchers=$(python3 "$REPO/plasma/apps.py" "$REPO/config/apps.conf" launchers)
  plasma_eval "$(sed "s|__LAUNCHERS__|$launchers|" "$REPO/plasma/panel.js")" >/dev/null
  rm -f "$NOOK_STATE/tray-seen"   # new tray: hide everything again
  ok "one auto-hiding bar: launcher + apps · colourful clock · tray"
fi

# ── 6a · desktop widgets on every screen ────────────────────────────────────
if [ "$DO_WIDGETS" = 1 ]; then
  step "desktop widgets: clock, system, apps on every screen"
  apps_json=$(python3 "$REPO/plasma/apps.py" "$REPO/config/apps.conf" json)
  # the apps card's footer opens the taskbar's app launcher
  launcher_cmd="dbus-send --session --type=method_call --dest=org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu"
  # 44px bar + its float margin
  for mode in remove add; do
    plasma_eval "$(printf '%s' "$layout_in" | python3 "$REPO/plasma/layout.py" "$apps_json" "$launcher_cmd" 64 $mode)" >/dev/null
    [ $mode = remove ] && sleep 2
  done
  ok "$(printf '%s' "$layout_in" | grep -c .) screen(s) filled; apps from config/apps.conf"
fi

# ── 6b · minimal tray ───────────────────────────────────────────────────────
step "tray: network, sound, microphone, battery; the rest in the ^ popup"
mkdir -p "$CFG/autostart"
cat > "$CFG/autostart/nook-tray.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Nook tray
Comment=Keeps the system tray down to network, sound, microphone and battery
Exec=$BIN/nook-tray
NoDisplay=true
# Plasma's tray only; nook-tile (Hyprland) runs its own autostart and has no use for it
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
DESKTOP
ok "nook-tray runs at login and hides new tray icons as apps start (started below)"

# ── 7 · shortcuts ───────────────────────────────────────────────────────────
if [ "$DO_KEYS" = 1 ]; then
  step "global shortcuts"
  python3 "$REPO/plasma/shortcuts.py" bind "$REPO/config/shortcuts.conf" "$BIN"
fi


# The tray watcher starts only now, once the restarted plasmashell is there to talk to.
pkill -f "$BIN/nook-tr[a]y" 2>/dev/null || true
(setsid -f "$BIN/nook-tray" >/dev/null 2>&1 &)

printf '\n%sλ nook applied.%s  %sMeta+/ shows every key · Meta opens the app launcher%s\n' \
  "$c_lav" "$c_off" "$c_muted" "$c_off"
printf '%s  Log out and back in once so window title bars (KWin) pick up the new icons and fonts.%s\n' "$c_muted" "$c_off"
printf '%s  Brave: run nook-brave once to load the Nook browser theme.%s\n' "$c_muted" "$c_off"
