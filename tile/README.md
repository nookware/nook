# λ nook-tile — Hyprland + Quickshell

The tiling half of nook v2. It's a second session next to Plasma, drawn in the **Ramen Sign** design
system (neutral black and greys, nine neons with one job each, cyan for focus), and it takes any palette.

```bash
./nook                                  # from the repo root: the TUI (pick "tile")
tile/install.sh --palette=ramen         # nook-tile alone: packages (sudo), then link the configs
tile/install.sh --palette=cocoa --no-deps
```

With **ramen**, the configs are symlinks into this folder (edits show up live). With any other palette,
they link to a recoloured copy in `~/.local/share/nook/tile-build`. Re-run the installer after editing.

| system | Hyprland 0.57+ | Quickshell | notes |
| --- | --- | --- | --- |
| **Nobara 44+** | COPR `sdegler/hyprland` | Nobara repo | Qt apps fully themed (KDE-aware qt6ct reads `NookRamen.colors`) |
| **Fedora 44+** | COPR `sdegler/hyprland` | COPR `errornointernet/quickshell` | same as Nobara. Breeze only if KDE is installed, Fusion otherwise |
| **Ubuntu 26.04+** and distros based on it (Mint, Pop!_OS, Kubuntu …) | PPA `cppiber/hyprland` | apt from 26.10 on; on 26.04 **built from source** (tag `v0.3.2`, a few minutes) | plain qt6ct uses the `nook-tile.conf` palette (`tile/qt/qt6ct.conf`), so KDE apps' own colour logic doesn't follow |
| Ubuntu 24.04, Debian | ✗ | ✗ | Qt 6.4 is too old (needs 6.9+); no Hyprland 0.57 packages |

The config uses Hyprland's **Lua** format, which is why Hyprland has to be 0.57 or newer.
On other distros, install Hyprland ≥ 0.57, Quickshell, kitty, mako and qt6ct yourself and run `--no-deps`.

Log out, pick **Hyprland** on the login screen. `SUPER ⇧ E` takes you back.

Hyprland reloads `nook.lua` and Quickshell reloads its folder when a file changes.
The shell, prompt and command-line tools are the shell part's (`./nook` → shell), and the login screen is the login part's.

| file | goes to | what |
| --- | --- | --- |
| `hypr/nook.lua` | `~/.config/hypr/nook.lua` (link) | Look, rules, autostart and **every keybind**. Hyprland 0.57 is configured in Lua. |
| `hypr/machine.lua` | `~/.config/hypr/machine.lua` (copied once, yours) | Monitors (DP-2 landscape, DP-1 portrait on the right), EurKEY layout. |
| `hypr/hyprland.lua` | `~/.config/hypr/hyprland.lua` | Just `require("machine")` and `require("nook")`. |
| `hypr/hyprlock.conf`, `hypridle.conf` | `~/.config/hypr/` (links) | Lock screen with the `NOOK` banner's shadow-block clock (`bin/nook-lockclock`, one fire → ice hue per row), cyan input. Locks after 10 min. |
| `quickshell/nook/` | `~/.config/quickshell/nook` (link) | The shell, started with `qs -c nook`. |
| `kitty/nook.conf` | `~/.config/kitty/` (link + `include`) | The palette, 90% opacity; `NOOK=1` and the axolotl fastfetch for the shell part. |
| `ssh/nook.conf` | `~/.ssh/nook.conf` (copy, mode 600, + `Include` at the end of `~/.ssh/config`) | `TERM=xterm-256color` for ssh, so `nano` & co. work on machines without kitty's terminfo (`Error opening terminal: xterm-kitty`). A `Host` block of your own above it wins. |
| `mako/config` | `~/.config/mako/` (link) | Notifications top-right: `[i]` / `[~]` / `[!!]`, critical ones in red. |
| `../shared/cursors/pixelcursors.py` | `~/.local/share/icons/Nook-{Pixel,Halo,Neon,Ember,Dusk,Sign}` (generated) | Pixel-art cursors in six styles, in the palette's colours. The default is **Neon** at size 20: a dark fill, a cyan neon-tube outline and a cyan glow. Pixel is the old Win95 / Mac classic look; Halo, Ember, Dusk and Sign are the others. Switch live with `hyprctl setcursor Nook-Ember 20`; `pixelcursors.py --sheet preview.png` draws them all side by side. |
| `systemd/hyprland-session.target` | `~/.config/systemd/user/` (link) | Starts `graphical-session.target` so xdg-desktop-portal runs (screen sharing, file dialogs). |
| `../shared/icons/build.sh <palette>` | `~/.local/share/icons/Nook-Ramen` or `Nook` (generated) | The rice's icon set (BeautyLine + Breeze symbolic) with one neon per category: files gold, dev aqua, comms cyan, network blue, system amber, media rose, time red, security orange, session cream. KDE apps read the icon theme from the shared `kdeglobals`, so `bin/nook-session-look` sets `Nook-Ramen` when Hyprland starts and puts Plasma's back when Plasma starts (a Plasma-only autostart entry). |
| `qt/qt6ct.conf` + `../palettes/kde/*.colors` | `~/.config/qt6ct/` | Qt/KDE apps in the palette: Breeze style, cyan selection and focus, your Plasma fonts and icons. Only the Hyprland session uses it (`QT_QPA_PLATFORMTHEME=qt6ct`). |

**Red is the accent** (start button, clock, the cyan → red window border and its halo, which turns with it, glows, hover in Qt apps). Orange takes over danger: urgent workspaces, errors, critical notifications, the lock button. The login screen (`shared/login/login.sh`) takes any palette, for SDDM and Plasma Login.

## The shell (Quickshell)

- **Bar** (`Bar.qml`), a 30px strip flush on the bottom edge of every screen, its modules as pills inside it. Windows keep 6px from it, as from the screen edges and each other. Coloured text in it glows in its own colour (`Neon`):
  - `λ nook` in cream opens the menu; right-click opens the control center's `nook` tab.
  - Workspaces 1–9 as dots: cyan bar = on this screen, grey = occupied, red = urgent. A click brings that workspace to this screen.
  - The focused window as a `[ app — title ]` tag.
  - The **clock pill**, on the right before `⏻`, is the overview and the control center's button. It shows a glowing dot for the keyboard layout (aqua = EurKEY, gold = German; click the dot to switch), the VT323 time, the date, and the battery as a thin glowing bar with its percentage (aqua and pulsing while charging, gold at 30 % and below, orange at 15 % and below), plus `mute` and an orange `●` when a tray app needs you. Click opens the control center (sound, net, bluetooth, tray apps, nook) and the pill gets a cyan ring and glow while it's open. Right-click switches the layout, middle-click mutes, scroll changes the volume. Everything that used to have its own pill (kb, net · bt, vol, tray) lives behind it.
  - CPU braille sparkline and RAM.
  - `⏻`: menu on left click, lock on right click.
- **Launcher / hack menu** (`Launcher.qml`, `SUPER SPACE` or `λ nook`): the design system's Launcher, live.
  - NOOK banner, `user@host`, kernel and uptime.
  - A `λ ~/ >` prompt with a blinking aqua block.
  - Pinned apps from `config/apps.conf` as `[01] ▢ name ...... binary`, with line icons in the category hue. Typing searches every app.
  - `SYS // LIVE` (cpu, ram, gpu, temp, net, workspaces), a hexdump of what you type, and the cat.
  - `[lock] [sleep] [reboot] [shutdown]`. Reboot and shutdown ask with a second click.
  - Keys (it all works without a mouse): `↑↓` or `Ctrl N`/`P` move through every result and the list scrolls, `PgUp`/`PgDn` jump 9, `⏎` runs, `Alt 1‥9` runs a visible row. `Tab` moves to the power buttons: `←→` pick, `⏎` presses (twice for reboot / shutdown), `Tab` or `Esc` go back, typing goes back and searches. Straight from the prompt: `Alt L` lock, `Alt S` sleep, `Alt R` reboot, `Alt P` shutdown (the last two press twice), or type it: `sh`, `reb`, `lock`, `sleep`, `off` … list the power action first, `⏎` runs it (twice for reboot / shutdown). `Esc` or a click outside closes.
  - **Browser tabs**: `@` lists every open tab, `@word` filters them, and any search of two letters or more shows matching tabs below the apps. `⏎` shows the tab and focuses its window, `Ctrl W` closes it. Needs the **nook tabs** extension, loaded once in Brave (or Chrome): `brave://extensions` → Developer mode → Load unpacked → `tile/browser/nook-tabs`. It talks only to `bin/nook-tabs`, which the browser starts itself (registered by `install.sh` for that extension id alone) and which listens on a socket only you can open, for three requests: list, show, close. No remote-debugging port, no access to pages.
- **Keyboard layout** (EurKEY / German, `kb_layout = "eu,de"` in `machine.lua`) shows as the dot in the clock pill. `SUPER K`, a click on the dot, or a right-click on the clock switches it.
- **Control center** (`ControlCenter.qml`, above the clock on the right), five tabs in the launcher's look. Open it with `SUPER A` (last tab), `SUPER N` (net), `SUPER ⇧ B` (bluetooth), a click on the clock, or right-click `λ nook` (nook tab). It works fully from the keyboard: `↑↓` (or `j k`) move the focus, `⏎` / space press, `←→` change a volume (`⇧` for 1 %), `m` mutes, `del` forgets / removes, `m` on a tray app opens its menu, `Tab` `⇧Tab` or `1‥5` switch tabs, `Esc` closes.
  - `audio`: output and input device to pick, volume and mic bars (click, drag or scroll), mute, and a mixer per app.
  - `net`: wifi on/off and networks by signal; it scans while the tab is open. Click to connect or disconnect. A new secured network asks for its password right in the row (`⏎` joins, `show` reveals it); a wrong one shows why and asks again. Known networks have `[forget]` (click twice). Wired links (from `nmcli`, without container veths) connect and disconnect with a click. Below them, **`NET // PROFILES`** lists every wired NetworkManager profile with `dhcp` or its static address. A click (or `⏎`) switches to it, and a click on the active one takes it down. A profile bound to a MAC or an interface goes to that adapter (shown as `→ eth0`; with a dock that passes the laptop's MAC through, the adapter with a cable wins). Any other profile goes to the adapter in `[on eth0 ⇄]`, which cycles through the adapters with a cable. Profiles whose adapter isn't plugged in are greyed out, and nmcli errors show in the panel. `bin/nook-wired list | up UUID [DEVICE] | down UUID` does the work. `settings` opens `nm-connection-editor`, or `nmtui` without it.
  - `bt`: bluetooth on/off, scan, devices with connect/disconnect and battery. A new device pairs, gets trusted and connects with one click; `[cancel]` stops pairing, `[forget]` (click twice) removes a paired one.
  - `apps`: the background apps (the tray) as a list. Click opens, right-click opens their menu. Also what's playing.
  - `nook`: what the shell shows, live. Every bar module (λ nook, workspaces, window, clock, cpu · ram, power), every desktop widget, the wallpaper's NOOK banner and dot grid, and the cheatsheet switch on and off with a click. The homelab hosts are added (`name` + `host` or `host:port`, `⏎`), changed (click a row) and removed (`[remove]`, click twice) here, and the weather place is set here. The switches are kept in `~/.config/nook/shell.json` (`Settings.qml`; only what's off is stored), hosts and place in `widgets.conf` (written by `nook-feed set|unset`, comments stay). Also over IPC: `qs -c nook ipc call nook toggle|on|off widget.srv`, `… nook list`.
- **Cheatsheet** (`CheatSheet.qml`): `SUPER /` shows it over every window on the focused screen (blurred behind); any key or click closes it. It can also sit on the wallpaper, under every window: the `cheatsheet` switch in the nook tab.
  - It reads the binds from `hyprctl binds -j`. Every bind in `nook.lua` with a description
    `"group: label"` shows up there, so `nook.lua` is the only list of keys.
  - Group colours: APPS amber, SETTINGS aqua (control center, net, bluetooth, keyboard), WINDOWS cyan, WORKSPACES blue, SYSTEM red.
- **Widgets** (`Widgets.qml`), top right. Landscape screens get two columns, portrait screens one:
  - `TIME // LOCAL` in the `NOOK` banner's shadow-block font (`███╗`), one fire → ice hue per row, and the ISO week.
  - `SYS // LIVE` with cpu / ram / disk `[████░░]` bars, net as a blue sparkline, and the CPU temperature. With an NVIDIA card also gpu and vram bars, a load sparkline, temperature, watts and fan (`nvidia-smi`).
  - `NOW // PLAYING` (MPRIS) with `[◀◀] [ ▮▮ ] [▶▶]`.
  - `WX // OUTSIDE`: weather now (symbol, temperature, feels-like, min/max, humidity, wind) and the next five 3-hour slots with rain chance, from wttr.in.
  - `SRV // HOMELAB`: your hosts with an up/down dot, a latency sparkline and the last ping. `host:port` checks a TCP port instead, for hosts that drop pings.
  - `CAL // NEXT`: the next events from a CalDAV server (Nextcloud works), with a countdown to the first one. The password sits in the keyring, not in a file: `nook-feed cal --setup`. The url can be the calendar home (`…/remote.php/dav/calendars/<user>/`) or the server's DAV root, which is followed to it.
  - `PROC // TOP`: the five busiest processes (idle ones by ram). Click a row, then click again within 3 s to end it; the session's own processes can't be ended.
  - Weather place, hosts and calendar are personal, so they live in `~/.config/nook/widgets.conf` (installed once from `config/widgets.example.conf`; place and hosts can also be set in the `nook` tab). A widget with nothing configured hides, and so does one switched off in the `nook` tab (it stops polling too). The shell usually starts before the wifi is up, so a failed weather or calendar fetch tries again after 30 s. `Feeds.qml` polls `bin/nook-feed`.
- **Wallpaper** (`Wallpaper.qml`), drawn live per screen: dot grid, scanlines, and the glowing `NOOK` banner.
- `Theme.qml` holds the tokens and `Stats.qml` the shared `/proc` numbers.

## Autostart

Apps in `~/.config/autostart` and `/etc/xdg/autostart` (Blip, KDE Connect …) run like under Plasma, through systemd's XDG autostart generator, which honours `OnlyShowIn`/`NotShowIn`. They start only once Quickshell owns the tray (`bin/nook-autostart start`), because tray apps register their icon once, when they start. `SUPER ⇧ R` restarts the running ones after the shell (`nook-autostart restart`), so their icons come back. `nook.lua` also puts `~/.local/bin` on the session's PATH, which the nook helpers (`nook-shot`, `nook-gamemode` …) need.

## If the shell crashes

Quickshell runs under `bin/nook-shell`, which starts it again within a second when it crashes
and shows a notification. A stop on purpose (`SUPER ⇧ R`, logout) ends it too. Quickshell keeps
its logs in RAM, so the crashed run's output is saved to `~/.local/state/nook/shell-crash-<time>.log`
first, where it survives a reboot. After five crashes in a minute it gives up and says so.

## Screen sharing

It goes through `xdg-desktop-portal-hyprland` (the picker appears when an app asks). Two things keep it working:
- KDE's `xwaylandvideobridge` is kept to Plasma (`NotShowIn=Hyprland`). Under Hyprland it opened shares by itself and looped on formats.
- Electron apps from Flatpak (Discord, Vesktop) run natively on Wayland (`ELECTRON_OZONE_PLATFORM_HINT=auto`), so they share through the portal instead of needing the bridge.

## Gaming

- **Global:** tearing allowed, VRR for fullscreen windows (`misc.vrr = 2`), direct scanout for fullscreen games.
- **Games** (`steam_app_<id>`, `gamescope`, `*.exe`) get a rule:
  - tearing (`immediate`) for the lowest latency
  - no idle lock while fullscreen
  - `content = "game"`
  - no blur or dimming
  - they keep rendering when the other screen has focus
- **NVIDIA:** `LIBVA_DRIVER_NAME`, `__GLX_VENDOR_LIBRARY_NAME` and `NVD_BACKEND` are set when the proprietary driver is loaded.
- **`SUPER G` game mode** (`bin/nook-gamemode`) turns animations, blur, shadows, dimming and gaps off. Press it again to reload the normal look.
- **`SUPER ⇧ P` screens** (`bin/nook-display`) toggles extend ⇄ duplicate: every other screen mirrors the focused one, upright in its own rotation (letterboxed between portrait and landscape), and all screens switch to the biggest resolution they share (a small beamer gets a native, readable picture; `nook-display duplicate 1280x720` picks one yourself). Extend is a config reload, so the layout stays in `machine.lua`. `nook-display only` keeps just the focused screen.
- **Steam launch options** worth using: `gamemoderun %command%` (CPU governor and priority), `mangohud %command%` (FPS overlay), or `gamescope -f -W 2560 -H 1440 -r 144 -- %command%` for games that misbehave with XWayland.

## Keys

| | |
| --- | --- |
| apps | `SUPER ⏎` kitty · `SUPER SPACE` menu · `SUPER E` dolphin · `SUPER B` browser (the open window, again = the next one; only starts one if none is open) · `SUPER ⇧ ⏎` btop |
| windows | `SUPER Q` close · `SUPER F` fullscreen · `SUPER V` float · `SUPER P` pseudo · `SUPER J` flip split · `SUPER ←↑→↓` focus · `SUPER ⇧ ←↑→↓` move · `SUPER` + drag |
| workspaces | 1–9, not tied to a screen; at login the screens show 1, 2 … from the left. `SUPER n` brings workspace n to the focused screen; if the other screen shows it, the two trade · `SUPER ⇧ n` sends the window to n · `SUPER S` scratchpad · `SUPER ALT S` to scratchpad. An unplugged screen's workspaces stay and `SUPER n` gets them back |
| settings | `SUPER A` control center (last tab) · `SUPER N` net (wifi, ethernet) · `SUPER ⇧ B` bluetooth · `SUPER K` keyboard EurKEY ⇄ German |
| system | `SUPER G` game mode · `SUPER ⇧ P` screens extend ⇄ duplicate · `SUPER L` lock · `SUPER ⇧ S` / `W` / `A` screenshot area / window / screen (also `PRINT`), saved to ~/Pictures/Screenshots + clipboard · `SUPER /` cheatsheet · `SUPER ⇧ R` reload shell · `SUPER ⇧ E` exit |

## Known gaps

- The configs **have not run on a real session yet**. The first login is the test. If
  Hyprland shows a config error bar, the error message names the line.
- Screens-off on idle (dpms) is left out because the Lua dispatcher arguments aren't documented yet.
- GTK apps don't have a Ramen theme yet. The recoloured icon set and the cava bars in the
  now-playing widget are still to do too.
