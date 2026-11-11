# λ nook v2

Two desktops, any palette, one script.

- **plasma**: a KDE Plasma 6 rice. Krohnkite tiling, a floating taskbar, desktop widgets, a key
  cheat-sheet on the wallpaper, its own icons, cursor, window frames and logout screen.
- **tile**: Hyprland 0.57 + Quickshell. A neon tiling desktop with a hack-menu launcher, a control
  center, the cheatsheet on the wallpaper and gaming tweaks. See [tile/README.md](tile/README.md).
- **shell**: zsh, the prompt (nook theme or starship) and the command-line tools (zoxide, eza, bat,
  delta, fd, ripgrep, fzf, fastfetch, btop, cava, git colours, yazi, lazygit, tldr, direnv, dust,
  duf, glow, opencode). Each one is optional.
- **wled**: WLED LED strips. Every palette becomes a WLED custom palette and a glow preset
  `nook · <palette>` (Noise 3 through network → comms → files → time), and the strips glow in that palette (devices in `config/wled.conf`).
- **login**: the login screen. The nook greeter for SDDM, or palette, cursor and wallpaper for
  Plasma Login.

Every part takes every **palette** (`palettes/*.json`):

| palette | look |
| --- | --- |
| **cocoa** | Warm espresso-brown surfaces, cream text, nine pastels. The original Plasma rice. |
| **ramen** | Ramen Sign: a late-night noodle shop. Neutral black and greys, nine neons, cyan focus, red accent. |

Both sessions sit side by side; pick one on the login screen and it remembers your choice.
Tested on Nobara 44 (Plasma 6.7, Hyprland 0.57.1, NVIDIA, two monitors with one portrait).

```bash
git clone https://github.com/nookware/nook.git && cd nook
./nook                      # the TUI: pick parts, palettes and shell tools, with live previews
```

`./nook` opens a menu (fzf):

- `space` turns a part on or off.
- `⏎` opens its options. For **plasma** and **tile**: the palette, every piece on its own (tile:
  bar and launcher, lock screen, look, terminal, notifications, tools, browser tabs, session
  fixes; plasma: taskbar, widgets, shortcuts, icons, cursor) and every package on its own, each
  with what it is for and whether it is installed already. For the shell: which tools and which prompt.
- **palette** sets one palette for every part.
- The pane on the right previews whatever is highlighted: the palette's colours, a bar, a
  prompt and icons, a mock-up of the desktop, what a shell tool does.
- `▶ install` shows the plan and asks before it runs anything. When it's done it offers the setup.
- **setup** (`./nook setup`) walks you through what nook can't guess, one question at a time,
  and every step can be skipped (`s`) or run alone later (`./nook setup screens`):
  - `screens`: order left to right, resolution and refresh rate, which way up, scale. Written to
    `~/.config/hypr/machine.lua`.
  - `keyboard`: the layouts (checked against the system's xkb list).
  - `widgets`: weather place, homelab hosts, the CalDAV calendar and its password in the keyring.
  - `shell`: zsh as your login shell.
  - `browser`: the default browser, and loading the nook tabs extension.
  - `session`: Hyprland preselected on the login screen.
  - `wled`: finds WLED controllers on your network and adds them to `config/wled.conf`.

  Before a file changes you see the difference and confirm it, and the old one is backed up to
  `~/.local/state/nook/`.

Your choices are remembered for next time. The package list with each distro's names (plasma, tile and every shell tool) is
`lib/packages.tsv`.

Without the TUI:

```bash
./nook install --plasma --tile --shell --login --palette=ramen      # everything in Ramen Sign
./nook install --tile --tile-palette=cocoa --no-deps                # nook-tile in cocoa, no sudo
./nook install --shell=zsh,omz,prompt-starship,zoxide,eza,bat       # just these shell parts
./nook install --tile-parts=hypr,shell,lock --packages=hyprland,quickshell,hyprlock   # exactly these
./nook setup screens keyboard   # only these setup steps
./nook palette cocoa         # switch every installed part to cocoa
./nook uninstall             # Plasma back to your pre-nook backup, login theme removed
```

- `--no-deps` skips packages and the login screen, so nothing runs with sudo.
- Plasma's part switches Plasma live, so it needs a Plasma session. Started from Hyprland, it is
  queued and applies itself at the next Plasma login.
- nook-tile needs Fedora/Nobara 44+ or Ubuntu 26.04+ (Hyprland ≥ 0.57 from COPR / PPA).
- The Plasma part also runs on Ubuntu/Kubuntu, Debian, Arch and openSUSE.

## Layout

```
nook                    the one entry point: TUI + command line
palettes/               cocoa.json, ramen.json: roles (grounds, text, focus, accent, one hue per
                        category) + 16 terminal colours; kde/ holds each palette's KDE colour scheme
plasma/                 the Plasma rice
  apply.sh              everything per-user, live (backs up first to ~/.local/state/nook/)
  deps.sh · uninstall.sh · migrate.sh
  themegen.py           Plasma style + Aurorae window frames
  wallpaper.py          wallpaper with the key cheat-sheet, per screen
  panel.js · layout.py · apps.py · shortcuts.py · krohnkite.py · cursors.py · zed.py
  theme/                plasmoids, logout screen, KWin script, Konsole, Zed, Brave
  bin/                  nook-keys, nook-tray, nook-brave
tile/                   Hyprland + Quickshell (see tile/README.md)
shared/
  shell/                install.sh, zshrc, bashrc, tools.sh, the nook zsh theme, starship.toml
  cli/                  bat, btop, cava, git/delta, ripgrep, fastfetch themes
  icons/                build.sh <palette>, icons.py, appicons.py, svg/ (the rice's own icons)
  cursors/              pixelcursors.py (Nook-Pixel)
  login/                login.sh (SDDM / Plasma Login), the SDDM theme, the login wallpaper
  wled/                 wled.py: palettes + glow presets on WLED devices (--scan, --dry-run, --remove)
lib/                    lib.sh, recolor.py (any palette → any palette), preview.py (the TUI's previews)
config/                 apps.conf (pinned apps), shortcuts.conf (Plasma keys + cheat-sheet)
```

**How palettes work.** Every file is drawn in one palette: the Plasma rice in cocoa, nook-tile and
the login in ramen. `lib/recolor.py` maps it to any other palette through the roles, so focus
stays focus and "files" stays "files". It handles `#rrggbb`, `#rrggbbaa`, `#aarrggbb`, `r,g,b`,
`38;2;r;g;b` and hyprlang's `rgb()`. To add a palette, drop a `palettes/<name>.json` with the
same roles next to the two others; the TUI lists it.

# The Plasma rice

## What you get

| piece | details |
| --- | --- |
| **Colours** | `Nook` Plasma colour scheme, used by the Breeze application style. |
| **Plasma style** | `nook`, generated from the design tokens. Flat cocoa taskbar with a hairline on top. Task buttons: a short faint bar while running, a tile plus a lavender bar when focused, a coral bar when asking for attention. Popups are rounded with a lavender ring. Everything else falls back to Breeze. |
| **Icons** | `Nook`: the BeautyLine line-icon theme (fetched at a pinned commit, GPL-3) repainted so each icon is **one pastel chosen by category**. Media is pink, security coral, time and transfers peach, files butter, dev mint, chat teal, web sky, system lavender and session lilac. App icons are categorised from their `.desktop` Categories, others by name. The arrows (the tray's `^` too) are thin line chevrons instead of BeautyLine's filled ones, and the Office category is a plain line document instead of the Microsoft Office logo. Apps BeautyLine has nothing for get a theme icon found under another of their names, or else a monogram tile in their category colour; apps whose `.desktop` file points at an image (snaps, for one) get a copy in `~/.local/share/applications` that names the theme icon instead (`shared/icons/appicons.py`; uninstall removes them). Underneath it, `Nook-Breeze` repaints Breeze's small symbolic icons (tray, toolbars) the same way. |
| **Cursor** | `Nook-Cursors`: **Posy's Cursor** (Michiel de Boer's design, Linux port by simtrami, CC BY-NC 4.0, fetched at a pinned commit and not vendored) recoloured by `plasma/cursors.py`. The shapes stay exactly Posy's; white becomes cream and black becomes cocoa, and the coloured bits (the spinning wait wheel, the "not allowed" sign) take the nearest pastel. Size 32, with 48–128 for scaled screens. |
| **Fonts** | JetBrains Mono for every UI font, with bold window titles. The Nerd Font build is used if that's the one installed. VT323 is fetched for pixel headings. |
| **Windows** | `Nook` Aurorae decoration (generated SVG). Cocoa title bar with the title on the left and bracketed `[_] [□] [x]` buttons on the right; close turns coral on hover. Square corners; the active window gets a 1px lavender ring and inactive ones a hairline. Blur is on. |
| **Tiling** | **Krohnkite** (MIT, a dynamic tiling KWin script, fetched at a pinned release and checksum-verified): every new window is tiled automatically, master on the left and the stack on the right, with 8px gaps. Each screen and virtual desktop keeps its own layout. Dialogs and plasmashell float. `Meta+F` floats or tiles a single window, and dragging a tile onto another swaps them. Keys below; Krohnkite's own defaults that clash with Plasma's (`Meta+L`, `Meta+I`, `Meta+D`, `Meta+.`) are cleared, and KWin's quick-tile keys go to Krohnkite (`Meta+Shift+←→` resize instead of sending a window to the next screen; `Meta+Alt+arrows` does that). The arrow keys cross screens: at the edge of a screen, focus jumps to the next screen and a moved window is sent there (`plasma/theme/kwin/nook-tiling`). On a portrait (90°) screen the split starts top/bottom: the master on top, the others side by side below it (a small patch to Krohnkite's tile layout, `plasma/krohnkite.py`); `Meta+Ctrl+Space` rotates from there. Settings: System Settings → Window Management → KWin Scripts → Krohnkite. |
| **Taskbar** | One floating bar along the bottom of the primary screen that **auto-hides**: push the mouse against the bottom edge anywhere to bring it back. Left: the filled rainbow hexagon-λ start button (set apart from the single-pastel line icons of the apps) and pinned apps. Centre: a colourful clock (a big rainbow `16:34` as tall as the app icons, with `fri 09.10` over `wk41 :47` beside it; click for a calendar). Right: the tray, its icons scaled to the same size as the apps. It's one bar rather than separate islands because Plasma only reveals an auto-hidden panel from the stretch of screen edge right under it. |
| **Desktop widgets** | Three custom Plasma widgets are placed on **every connected screen**, in the space the wallpaper leaves free. Everything sits on Plasma's 16px widget grid, and the wallpaper's cards are snapped to the same grid, so the widget frames line up exactly with the cheat-sheet and whoami cards, with the same 32px gaps. On landscape screens: clock and apps level with the cheat-sheet, the system card below them from the whoami card's top to above the banner. On portrait screens: stacked between the cards and the banner, as wide as the cards. `TIME // LOCAL` is a big clock drawn with `#` in monospace, one pastel per digit, with date, ISO week and day of month. `SYS // LIVE` shows CPU/GPU/RAM/disk as `[████░░]` bars with temperatures, network up/down as sparklines, and uptime. `APPS // PINNED` has numbered app tiles that scale with the card; its footer opens the taskbar's app launcher. |
| **Tray** | Only network, sound, microphone and battery stay visible. Everything else, Plasma's own entries and app icons alike, goes into the `^` popup. `nook-tray` runs at login and hides tray icons from apps that start later. Each entry is hidden only the first time it appears, so anything you set to "Always shown" stays. Edit `SHOW` in `plasma/bin/nook-tray` to change the list. |
| **Wallpaper** | Rendered **per screen at its real size**, so rotated or portrait monitors get a stacked layout. It has a dot grid, a faint ASCII skull (only without the desktop widgets), a **key cheat-sheet** (three columns, two when the screen is too narrow), a `whoami` card and the rainbow `NOOK` banner. The lock screen gets it too. |
| **Login screen** | `shared/login/sddm/nook`, an SDDM theme in plain QtQuick: the wallpaper's dot grid, the desktop's `#` clock, a terminal-style `LOGIN // TTY` card and the rainbow banner. `user ‹ nbax ›`, `pass ▶ ••••` and `session ‹ plasma (wayland) ›` rows (Tab moves between them, ←→ change the user or session, ⏎ logs in), and `[ suspend ] [ reboot ] [ shut down ]` with the taskbar's hover bars. A failed login shakes the card; caps lock gets a warning. Other screens get just the clock and banner. Also uses the Nook cursor. Installed by `shared/login/login.sh` (sudo) to `/usr/share/sddm/themes/nook`, picked by `/etc/sddm.conf.d/zz-nook.conf`; `shared/login/login.sh --remove` undoes it. Preview without logging out: `sddm-greeter-qt6 --test-mode --theme shared/login/sddm/nook`. **Plasma Login** (Plasma 6.6+, the default on Fedora/Nobara now) has a built-in greeter that takes no themes, so `shared/login/login.sh` gives it Nook's colours, Plasma style, font and cursor (in the `plasmalogin` user's config) and the desktop's wallpaper (in `/etc/plasmalogin.conf`) instead. System Settings → Login Screen → "Apply Plasma Settings" overwrites that; run `shared/login/login.sh` again to restore it. **One look for both sessions** (Plasma and nook-tile): by default the **Ramen Sign** look (neutral greys and neons, cyan focus, the `NookRamen` colours, Nook-Pixel cursor, a black wallpaper with the glowing `NOOK` banner from `shared/login/wallpaper.py`; the SDDM theme reads `palette=ramen` from its `theme.conf`). `shared/login/login.sh --pastel` brings back the cocoa look. |
| **Logout screen** | `plasma/theme/look-and-feel/org.nook.desktop`, a global theme with only a logout screen: the login screen's dot grid, `#` clock and banner around a `SESSION // POWER` card of `[ sleep ] [ restart ] [ shut down ] [ log out ] [ cancel ]` (←→ or Tab pick, ⏎ runs, Esc cancels). Shut down or restart from the menu counts down 30 s. Everything else (splash, lock screen) is Breeze. `apply.sh` sets just its name, since `plasma-apply-lookandfeel` would also reset the panel. Preview: `/usr/libexec/ksmserver-logout-greeter --windowed` (the buttons work, so press Esc). |
| **Lock screen** | Plasma's own (since Plasma 6.6 it belongs to the desktop shell, not the global theme) in Nook colours, font and the primary screen's wallpaper. |
| **Terminal** | **kitty** is the default terminal (`Meta+Return`, and Plasma's default terminal for Dolphin & co.), the same one and the same config as in nook-tile. It runs **zsh with oh-my-zsh** and the `nook` theme: a two-line prompt (`╭─λ user@host ─ ~/path ─  branch ✓` / `╰─❯`). The right side shows the conda/venv env, how long the last command took, a failed command's exit code, and the time. Autosuggestions and syntax highlighting are in the pastels. Your own `~/.zshrc` is kept; one line is added at its top. The palette's 16 colours at 90% opacity (`tile/kitty/nook.conf`). When nook-tile is installed, its linked `~/.config/kitty/nook.conf` is kept, so both sessions share one terminal look; otherwise apply.sh copies it in Plasma's palette. `~/.config/kitty/kitty.conf` gets `include nook.conf` and zsh as the shell. **Konsole stays as the fallback** on `Ctrl+Alt+T`, with the same look in its `Nook` profile and no toolbars (menus via Ctrl+Shift+M or right-click).
| **fastfetch** | Runs once when a Nook terminal opens (`theme/fastfetch`). A steaming mug with `n o o k` under it, then three cards like the wallpaper's: `SYS //` (os, kernel, packages, uptime), `DESK //` (Plasma, KWin and whether Krohnkite tiles, the colour scheme, icons and Plasma style in use, cursor, font, terminal, shell, each screen) and `HW //` (CPU with temperature, GPUs, and memory, disk and battery as `[████░░]` bars like the desktop widget), ending in the nine pastels. |
| **Brave** | `plasma/theme/brave/nook`: a browser theme in the same cocoa and lavender palette. Chromium only installs local themes through its own UI, so run `nook-brave` once: it opens the extensions page, copies the theme's path to the clipboard and tells you the two clicks (Developer mode → Load unpacked). |
| **Zed** | `plasma/theme/zed/nook.json`: a Zed theme in the same cocoa and pastel palette (lavender keywords and focus, mint strings, sky functions, butter types). It goes into the native (`~/.config/zed`) and the Flatpak (`~/.var/app/dev.zed.Zed/config/zed`) config, whichever is there. `settings.json` gets `theme` and JetBrains Mono as buffer and UI font; the file's other settings and comments stay as they are. Zed picks it up live. |
| **Shell tools** | Installed by `deps.sh` and set up in `shared/shell/tools.sh` (zsh, and bash in Nook terminals). Each one only kicks in when it's installed. **zoxide** sits behind `cd`: it learns where you go, so `cd proj` jumps to `~/code/proj`, plain paths work as before, and `cdi` picks with fzf. **eza** behind `ls` (`ll`, `la` with git status, `lt` for a tree). **bat** behind `cat`, as the man pager and as the fzf `Ctrl+T` preview. **fd** feeds fzf, and **ripgrep** (`rg`) gets smart-case and pastel matches. **fzf** (`Ctrl+R`, `Ctrl+T`, `Alt+C`) uses the palette everywhere. **yazi** is the file manager in the terminal: `y` opens it, and quitting with `q` leaves you in the folder you ended up in. **lazygit** (`lg`) is git as a TUI, in the palette, with your own `~/.config/lazygit/config.yml` loaded on top. **tldr** (tealdeer) shows short examples instead of the man page, **direnv** loads a folder's `.envrc` when you `cd` in, **dust** and **duf** show what fills the disk and how full each one is, **glow** renders markdown (`md README.md`), and **opencode** (`oc`) is a coding agent in the terminal with a theme generated from the palette (`lib/opencode_theme.py`); log in to providers with `opencode auth login` or `/connect`. On Fedora, lazygit comes from the COPR `atim/lazygit`. |
| **git** | `shared/cli/git/gitconfig`, included from `~/.gitconfig` (your own settings stay): pastel status, branch and diff colours, `git lg` (a one-line graph), `git st`, `git last`, zdiff3 conflicts. **delta** is the pager when it's installed (`shared/cli/git/delta.gitconfig`): line numbers, `n`/`N` to jump between files, coral and mint diff backgrounds, and syntax highlighting with the `Nook` bat theme (`shared/cli/bat/Nook.tmTheme`, the same colours as the Zed theme). |
| **Extras** | Themes for btop and cava (rainbow bars). |

## Pinned apps

`config/apps.conf` lists the pinned apps, used by both the taskbar and the desktop card. Each line
has a label, a category colour and the `.desktop` ids to try, so one line covers the native,
Flatpak and Snap builds of an app. If a pinned app isn't installed, its slot goes to the first
installed app from the `[fill]` list below it (Zed, VS Code, Firefox, Zen, Spotify, Signal,
Obsidian, Kate, System Monitor), so the card is always full. Edit it and run `./nook install --plasma --no-deps`.

## Shortcuts

`config/shortcuts.conf` is the **single source** for the key bindings *and* the wallpaper
cheat-sheet. A row with a command gets bound as a global shortcut, live over D-Bus, with no
logout needed. A row without one is a Plasma default and only shows on the wallpaper. Edit it,
then re-run `./nook install --plasma --no-deps`.

| keys | does |
| --- | --- |
| `Meta+Return` | terminal (kitty) |
| `Ctrl+Alt+T` | Konsole, the fallback terminal |
| `Meta+/` | show every shortcut in a terminal (`nook-keys`) |
| `Meta+B` | browser |
| `Meta+Shift+Return` | btop |
| `Meta+Alt+V` | cava |
| `Meta+←↑→↓` | focus the tile in that direction, or the next screen at the edge |
| `Meta+Alt+←↑→↓` | swap with the tile on that side, or send the window to the next screen |
| `Meta+Shift+←↑→↓` | shrink (← ↑) or grow (→ ↓) the window, tiled or floating |
| `Meta+Ctrl+Return` | make the window the master |
| `Meta+T` / `Meta+M` | tile / monocle layout (`Meta+Shift+Space` cycles all layouts, `Meta+Ctrl+Space` rotates) |

## Multi-monitor and rotation

Screen sizes come from plasmashell's own `screenGeometry()`. Rotation is already applied there,
so a 90° monitor reports e.g. 1440×2560 and gets a portrait wallpaper. The taskbar goes on the
primary screen. Plug in or rotate a monitor? Run `./nook install --plasma --no-deps` again.
