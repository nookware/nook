-- ── nook-tile · Ramen Sign ──────────────────────────────────────────────────
-- Look, rules, autostart and keybinds for Hyprland 0.57+ (Lua config).
-- Loaded from ~/.config/hypr/hyprland.lua with require("nook"); this file is a
-- symlink into the repo, so edit it there. Hyprland reloads on save.
--
-- Every bind gets a description "group: label". The Quickshell cheatsheet reads
-- them from `hyprctl binds -j`, so this file is the only list of key bindings.

-- palette colours (written with # so lib/recolor.py can switch the palette)
local C = {
    bg000 = "#060606", bg100 = "#0d0d0d", bg200 = "#141414", line = "#343434",
    cyan  = "#45c8e6", red = "#ff6458",
}
local function rgba(hex, a) return "rgba(" .. hex:gsub("#", "") .. (a or "ff") .. ")" end

local mod      = "SUPER"
local term     = "kitty"
local files    = "dolphin"
local browser  = [[sh -c 'gtk-launch "$(xdg-settings get default-web-browser)"']]
local menu     = "qs -c nook ipc call launcher toggle"

-------------------------------------------------------------------------------
-- autostart
-------------------------------------------------------------------------------
hl.on("hyprland.start", function()
    -- environment into systemd/dbus, then graphical-session.target (xdg-desktop-portal needs it),
    -- then the shell, so Quickshell finds the portal already running. The autostart apps come
    -- last (bin/nook-autostart): it waits until qs owns the tray watcher, otherwise Blip, KDE
    -- Connect … start without a tray, never show their icon and look like they didn't start.
    -- pam_kwallet_init hands the session to the ksecretd that SDDM started with the login password:
    -- it unlocks the wallet and serves org.freedesktop.secrets. Plasma runs it itself, but its
    -- autostart entry has X-systemd-skip, so here nobody would, and Nextcloud (started by the
    -- session target) found no keychain and asked for a fresh login every boot.
    -- command -p: the system one, not a copy a PATH entry (conda …) may put first
    hl.exec_cmd("command -p dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP "
        .. "HYPRLAND_INSTANCE_SIGNATURE DISPLAY QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE XDG_DATA_DIRS XDG_MENU_PREFIX "
        .. "&& { [ -x /usr/libexec/pam_kwallet_init ] && /usr/libexec/pam_kwallet_init; true; } "
        .. "&& systemctl --user start hyprland-session.target hyprpolkitagent "
        .. "; kbuildsycoca6 >/dev/null 2>&1; nook-session-look hyprland; { nook-autostart start & }; exec nook-shell")  -- Ramen icons for KDE apps, then the shell (restarted if it crashes)
    hl.exec_cmd("mako")                                 -- notifications
    hl.exec_cmd("hypridle")                             -- lock when idle
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop hyprland-session.target")
end)

-- Flatpak apps (browsers too) for the launcher, xdg-settings and gtk-launch: start-hyprland skips
-- /etc/profile.d/flatpak.sh, so the session would only see /usr/share/applications
local home = os.getenv("HOME")
local data_dirs = os.getenv("XDG_DATA_DIRS")
if data_dirs == nil or data_dirs == "" then data_dirs = "/usr/local/share:/usr/share" end
for _, dir in ipairs({ "/var/lib/flatpak/exports/share", home .. "/.local/share/flatpak/exports/share" }) do
    if not (":" .. data_dirs .. ":"):find(":" .. dir .. ":", 1, true) then data_dirs = dir .. ":" .. data_dirs end
end
hl.env("XDG_DATA_DIRS", data_dirs)
-- ~/.local/bin for the nook helpers (nook-shot, nook-gamemode, nook-display, nook-session-look,
-- nook-autostart …): the login session's PATH doesn't have it, so every bind and the start chain
-- that calls them by name failed without a word.
local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"
if not (":" .. path .. ":"):find(":" .. home .. "/.local/bin:", 1, true) then
    hl.env("PATH", home .. "/.local/bin:" .. path)
end
-- KDE's app database (ksycoca: Dolphin's "Open with", default apps for images, PDFs …) is built
-- from <prefix>applications.menu. Plasma sets the prefix itself; without it kbuildsycoca6 finds no
-- /etc/xdg/menus/applications.menu and Dolphin knows no apps (Gwenview, Okular … missing).
hl.env("XDG_MENU_PREFIX", "plasma-")

hl.env("XCURSOR_THEME", "Nook-Pixel")     -- old-school pixel cursors (shared/cursors/pixelcursors.py)
hl.env("XCURSOR_SIZE", "16")
hl.env("HYPRCURSOR_SIZE", "16")
-- Qt apps: qt6ct (the KDE-aware build) with the NookRamen colour scheme, Breeze style, Nook icons.
-- Only this session reads ~/.config/qt6ct, so Plasma keeps its pastel Nook scheme.
-- Plain qt6ct (Ubuntu) only hands over a QPalette, which Kirigami apps (Discover, System Settings)
-- ignore, and Qt5 apps can't load it at all: there KDE's own platform theme (Qt5 and Qt6) does
-- the job, reading colours and icons from kdeglobals.
local function qt6ct_kde_aware()
    local probe = io.popen([[ldd "$(command -v qt6ct)" 2>/dev/null | grep -c KF6ColorScheme]])
    if not probe then return true end
    local hits = tonumber(probe:read("*l") or "0") or 0
    probe:close()
    return hits > 0
end
hl.env("QT_QPA_PLATFORMTHEME", qt6ct_kde_aware() and "qt6ct" or "kde")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

-- NVIDIA (proprietary driver): VA-API, GLX vendor and Electron on Wayland
local nv = io.open("/proc/driver/nvidia/version", "r")
if nv then
    nv:close()
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
end
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-------------------------------------------------------------------------------
-- look
-------------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 6,                                -- gap-in
        gaps_out    = 6,                                -- edge (= gap-in): screen edges, the bar
        border_size = 2,
        col = {
            -- the neon sign: cyan → red, slowly rotating (borderangle below)
            active_border   = { colors = { rgba(C.cyan), rgba(C.red) }, angle = 45 },
            inactive_border = rgba(C.line, "cc"),
        },
        layout           = "dwindle",
        resize_on_border = true,
    },

    decoration = {
        rounding         = 4,                           -- radius-md: barely rounded
        rounding_power   = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.92,
        dim_inactive     = true,
        dim_strength     = 0.08,
        blur = {
            enabled = true,
            size    = 6,
            passes  = 2,
        },
        shadow = {
            enabled        = true,
            range          = 12,                        -- about the bar's neon halo
            render_power   = 3,
            -- glow-focus halo in the border's cyan → red; the angle turns with it (below)
            color          = { colors = { rgba(C.cyan, "66"), rgba(C.red, "66") }, angle = 45 },
            color_inactive = "rgba(00000066)",
        },
    },

    animations = { enabled = true },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        background_color         = "rgb(" .. C.bg000:gsub("#", "") .. ")",
    },

})

hl.curve("snap", { type = "bezier", points = { { 0.2, 0.9 }, { 0.1, 1.0 } } })
hl.animation({ leaf = "windows",     enabled = true, speed = 4,  bezier = "snap",    style = "popin 85%" })
hl.animation({ leaf = "fade",        enabled = true, speed = 4,  bezier = "default" })
hl.animation({ leaf = "layers",      enabled = true, speed = 4,  bezier = "snap",    style = "fade" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 4,  bezier = "snap",    style = "slide" })
hl.animation({ leaf = "border",      enabled = true, speed = 8,  bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 80, bezier = "default", style = "loop" })

-- the halo turns with the border. Hyprland rotates gradient borders (borderangle) but not shadow
-- gradients, so a timer turns the shadow's angle the same way: one turn per 8 s (speed 80), eased
-- like the "default" bezier (0, .75) (.15, 1). A reload stops the old timer before starting anew.
local GLOW_MS, GLOW_LOOP = 50, 8000
local function bezier(t)               -- y on the "default" curve at x = t (bisection on x)
    local function at(a, b, u) return 3 * a * u * (1 - u) ^ 2 + 3 * b * u ^ 2 * (1 - u) + u ^ 3 end
    local lo, hi = 0, 1
    for _ = 1, 20 do
        local mid = (lo + hi) / 2
        if at(0, 0.15, mid) < t then lo = mid else hi = mid end
    end
    return at(0.75, 1, (lo + hi) / 2)
end
if _G.nook_glow_timer then _G.nook_glow_timer:set_enabled(false) end
local glow_tick = 0
_G.nook_glow_timer = hl.timer(function()
    glow_tick = (glow_tick + 1) % (GLOW_LOOP // GLOW_MS)
    local angle = (45 + 360 * bezier(glow_tick * GLOW_MS / GLOW_LOOP)) % 360
    hl.config({ decoration = { shadow = {
        color = { colors = { rgba(C.cyan, "66"), rgba(C.red, "66") }, angle = math.floor(angle) },
    } } })
end, { timeout = GLOW_MS, type = "repeat" })

-------------------------------------------------------------------------------
-- layer surfaces (Quickshell) and window rules
-------------------------------------------------------------------------------
for _, ns in ipairs({ "nook-bar", "nook-cheatsheet", "nook-widgets", "nook-launcher", "nook-control" }) do
    hl.layer_rule({ match = { namespace = "^" .. ns .. "$" }, blur = true, ignore_alpha = 0.05 })
end

-- dialogs and pickers float
hl.window_rule({ match = { class = "^(org.kde.polkit-kde-authentication-agent-1|hyprpolkitagent|pavucontrol|org.pulseaudio.pavucontrol|nm-connection-editor|blueman-manager)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File|Save File|Open Folder|Choose Files?).*$" }, float = true })
hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
-- xwaylandvideobridge (autostarted for Plasma, shares screens to X11 apps) maps a real window;
-- keep it working but invisible instead of tiling it onto the workspace
hl.window_rule({
    name             = "xwaylandvideobridge",
    match            = { class = "^xwaylandvideobridge$" },
    float            = true,
    opacity          = "0.0 override",
    no_anim          = true,
    no_initial_focus = true,
    no_focus         = true,
    no_blur          = true,
    max_size         = "1 1",
})

-------------------------------------------------------------------------------
-- gaming: tearing for games, VRR in fullscreen, direct scanout, no lock mid-game
-------------------------------------------------------------------------------
hl.config({
    general = { allow_tearing = true },   -- only windows with `immediate` tear
    misc    = { vrr = 2 },                -- variable refresh rate for fullscreen windows
    render  = { direct_scanout = 2 },     -- skip compositing for fullscreen games
})
-- Steam/Proton games (steam_app_<id>), gamescope, Wine/Lutris .exe windows
hl.window_rule({
    name             = "games",
    match            = { class = "^(steam_app_[0-9]+|gamescope|.*\\.exe)$" },
    immediate        = true,          -- tearing: lowest latency (needs allow_tearing)
    idle_inhibit     = "fullscreen",  -- hypridle doesn't lock while you play fullscreen
    content          = "game",        -- tells direct scanout / VRR it's a game
    no_blur          = true,
    no_dim           = true,
    render_unfocused = true,          -- keeps rendering on the other screen
})
-- Steam's own small windows float
hl.window_rule({ match = { class = "^steam$", title = "^(Friends List|Steam Settings|Properties.*|.* - Chat|Screenshot Manager)$" }, float = true })

-------------------------------------------------------------------------------
-- workspaces: 1–9, they wander between screens
-------------------------------------------------------------------------------
-- At login the screens show 1, 2 … from left to right. SUPER n brings workspace n to the focused
-- screen. If n is showing on another screen, the two screens trade: that one gets the workspace
-- you were on. A workspace belongs to no screen, so the numbers move with what you do. When a
-- screen is unplugged its workspaces stay (Hyprland parks them on another screen) and SUPER n
-- brings them back.
local function screens()
    local ms = {}
    for _, m in ipairs(hl.get_monitors()) do
        if not m.is_mirror then table.insert(ms, m) end
    end
    table.sort(ms, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return ms
end

local function find_monitor(name)
    for _, m in ipairs(hl.get_monitors()) do
        if m.name == name then return m end
    end
end

local function find_workspace(n)
    for _, w in ipairs(hl.get_workspaces()) do
        if w.id == n then return w end
    end
end

-- show workspace n on screen `here` (a monitor name; default: the focused screen)
function nook_show_workspace(n, here)
    local mon = here and here ~= "" and find_monitor(here) or hl.get_active_monitor()
    if not mon or not n or n < 1 or n > 9 then return end
    here = mon.name
    local cur = mon.active_workspace and mon.active_workspace.id
    if cur ~= n then
        local ws = find_workspace(n)
        if ws and ws.monitor and ws.monitor.name ~= here then
            local there = ws.monitor.name
            local visible = ws.monitor.active_workspace and ws.monitor.active_workspace.id == n
            hl.dispatch(hl.dsp.workspace.move({ workspace = n, monitor = here }))
            -- it was on the other screen: that screen takes the one we had
            if visible and cur and cur > 0 then
                hl.dispatch(hl.dsp.workspace.move({ workspace = cur, monitor = there }))
            end
        end
    end
    hl.dispatch(hl.dsp.focus({ workspace = n }))
    -- a new workspace opens on the focused screen, which a click on another bar isn't
    local ws = find_workspace(n)
    if ws and ws.monitor and ws.monitor.name ~= here then
        hl.dispatch(hl.dsp.workspace.move({ workspace = n, monitor = here }))
        hl.dispatch(hl.dsp.focus({ workspace = n }))
    end
end

-- at login: screen s (left to right) shows workspace s, the leftmost one keeps the focus
hl.on("hyprland.start", function()
    local ms = screens()
    for s = math.min(#ms, 9), 1, -1 do nook_show_workspace(s, ms[s].name) end
end)

-------------------------------------------------------------------------------
-- keybinds  (description = "group: label" → cheatsheet)
-------------------------------------------------------------------------------
local function bind(keys, dsp, desc, opts)
    opts = opts or {}
    opts.description = desc
    hl.bind(keys, dsp, opts)
end
local function M(k) return mod .. " + " .. k end
local function MS(k) return mod .. " + SHIFT + " .. k end

-- apps
bind(M("RETURN"),  hl.dsp.exec_cmd(term),              "apps: terminal")
bind(M("SPACE"),   hl.dsp.exec_cmd(menu),              "apps: hack menu")
bind(M("A"),       hl.dsp.exec_cmd("qs -c nook ipc call control last"),         "settings: control center")
bind(M("N"),       hl.dsp.exec_cmd("qs -c nook ipc call control toggle net"),   "settings: net · wifi, ethernet")
bind(MS("B"),      hl.dsp.exec_cmd("qs -c nook ipc call control toggle bt"),    "settings: bluetooth")
bind(M("E"),       hl.dsp.exec_cmd(files),             "apps: files")
-- SUPER B goes to the browser you have open (the last used window; again → the next one) and
-- only starts one when there is none. Web apps (brave --app) are their own class and don't count.
local browser_classes = { ["brave-browser"] = true, ["google-chrome"] = true, ["chromium"] = true,
                          ["chromium-browser"] = true, ["firefox"] = true, ["zen"] = true, ["librewolf"] = true }
function nook_focus_browser()
    local wins = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and browser_classes[w.class] and not (w.workspace and w.workspace.id < 0) then
            table.insert(wins, w)
        end
    end
    if #wins == 0 then hl.dispatch(hl.dsp.exec_cmd(browser)); return end
    table.sort(wins, function(a, b) return a.focus_history_id < b.focus_history_id end)
    local pick = wins[1]
    -- already in the browser: cycle through its windows, the one used longest ago next
    if pick.active and #wins > 1 then pick = wins[#wins] end
    hl.dispatch(hl.dsp.focus({ window = "address:" .. pick.address }))
end
bind(M("B"),       function() nook_focus_browser() end, "apps: browser (the open one)")
bind(MS("RETURN"), hl.dsp.exec_cmd(term .. " -e btop"), "apps: btop")

-- windows
bind(M("Q"),       hl.dsp.window.close(),                     "windows: close")
bind(M("F"),       hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" }),              "windows: fullscreen")
bind(M("V"),       hl.dsp.window.float({ action = "toggle" }), "windows: float / tile")
bind(M("P"),       hl.dsp.window.pseudo(),                    "windows: pseudotile")
bind(M("J"),       hl.dsp.layout("togglesplit"),              "windows: flip split")
for _, d in ipairs({ "left", "up", "right", "down" }) do
    local arrows = { left = "←", up = "↑", right = "→", down = "↓" }
    bind(M(d),  hl.dsp.focus({ direction = d }),       "windows: focus " .. arrows[d])
    bind(MS(d), hl.dsp.window.move({ direction = d }), "windows: move " .. arrows[d])
end
bind(M("mouse:272"), hl.dsp.window.drag(),   "windows: drag = move",   { mouse = true })
bind(M("mouse:273"), hl.dsp.window.resize(), "windows: drag = resize", { mouse = true })

-- workspaces
for n = 1, 9 do
    bind(M(tostring(n)),  function() nook_show_workspace(n) end, "workspaces: bring here (swaps screens) " .. n)
    bind(MS(tostring(n)), hl.dsp.window.move({ workspace = n }),  "workspaces: send window to " .. n)
end
bind(M("S"),          hl.dsp.workspace.toggle_special("scratch"),         "workspaces: scratchpad")
bind(mod .. " + ALT + S", hl.dsp.window.move({ workspace = "special:scratch" }), "workspaces: to scratchpad")

-- system
bind(M("L"),     hl.dsp.exec_cmd("loginctl lock-session"),                         "system: lock")
bind(M("K"),     hl.dsp.exec_cmd("hyprctl switchxkblayout all next && qs -c nook ipc call kb refresh"),              "settings: keyboard eu ⇄ de")
-- screenshots: saved to ~/Pictures/Screenshots, copied, notified (bin/nook-shot); SUPER ⇧ S like Plasma
bind(MS("S"),    hl.dsp.exec_cmd("nook-shot area"),                                "system: screenshot area")
bind(MS("W"),    hl.dsp.exec_cmd("nook-shot window"),                              "system: screenshot window")
bind(MS("A"),    hl.dsp.exec_cmd("nook-shot screen"),                              "system: screenshot screen")
hl.bind("PRINT",    hl.dsp.exec_cmd("nook-shot area"))
hl.bind(MS("PRINT"), hl.dsp.exec_cmd("nook-shot screen"))
bind(M("slash"), hl.dsp.exec_cmd("qs -c nook ipc call cheatsheet peek"),           "system: this cheatsheet")
-- kded6 grabs the tray name while qs is down, and tray apps only register once: so stop kded6,
-- and restart the running autostart apps once the new qs has the tray (bin/nook-autostart)
bind(MS("R"),    hl.dsp.exec_cmd("pkill -x kded6; pkill -x qs; sleep 0.3; { nook-autostart restart & }; exec nook-shell"), "system: reload shell")
bind(MS("E"),    hl.dsp.exit(),                                                    "system: exit hyprland")
bind(M("G"),     hl.dsp.exec_cmd("nook-gamemode"),                                 "system: game mode on / off")
bind(MS("P"),    hl.dsp.exec_cmd("nook-display"),                                  "system: screens extend ⇄ duplicate")

-- media keys (no description: not on the cheatsheet)
local L = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), L)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), L)
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), L)
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), L)
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
