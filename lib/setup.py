#!/usr/bin/env python3
"""./nook setup: what nook can't guess, one question at a time. Every step can be skipped.

  ./nook setup                 every step
  ./nook setup screens wled    only those
steps: screens keyboard widgets shell browser session wled

⏎ takes the [default], "s" skips a step, "q" ends the setup. Files nook changes are backed up
to ~/.local/state/nook/ first, and you see the change before it is written.
"""
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOME = Path.home()
CFG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "nook"
MACHINE = CFG / "hypr/machine.lua"
STEPS = ["screens", "keyboard", "widgets", "shell", "browser", "session", "wled"]

MINT, BUTTER, CORAL, LAV, MUTED, OFF = ("\033[38;2;166;230;191m", "\033[38;2;242;226;155m",
                                        "\033[38;2;247;165;154m", "\033[38;2;196;178;245m",
                                        "\033[38;2;140;140;140m", "\033[0m")


class Skip(Exception): pass
class Quit(Exception): pass


def say(*a): print(" ", *a)
def ok(m): print(f"  {MINT}[OK]{OFF} {m}")
def warn(m): print(f"  {BUTTER}[!!]{OFF} {m}")
def dim(m): return f"{MUTED}{m}{OFF}"


def ask(q, default=""):
    try:
        a = input(f"  {LAV}?{OFF} {q}" + (f" {dim('[' + default + ']')}" if default else "") + " ").strip()
    except EOFError:
        raise Quit
    if a == "q": raise Quit
    if a == "s": raise Skip
    return a or default


def yes(q, default=True):
    a = ask(q, "Y/n" if default else "y/N").lower()
    return a.startswith("y") if a not in ("y/n", "") else default


def choose(q, options, default=0):
    """options: [(value, label)] → value"""
    for i, (_, label) in enumerate(options, 1):
        say(f"{dim(str(i) + ')')} {label}")
    while True:
        a = ask(q, str(default + 1))
        if a.isdigit() and 1 <= int(a) <= len(options):
            return options[int(a) - 1][0]
        warn(f"a number from 1 to {len(options)}, s to skip")


def run(cmd, timeout=10, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)
    except (OSError, subprocess.TimeoutExpired):
        return None


def backup(path):
    if path.exists():
        STATE.mkdir(parents=True, exist_ok=True)
        dest = STATE / f"{path.name}.{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(path, dest)
        return dest


def write_checked(path, old, new):
    """show the change, ask, back up, write"""
    if old == new:
        ok(f"{path.name} already says that")
        return False
    print()
    for line in difflib.unified_diff(old.splitlines(), new.splitlines(), lineterm="", n=1):
        if line.startswith(("---", "+++")): continue
        col = MINT if line.startswith("+") else CORAL if line.startswith("-") else MUTED
        print("   " + col + line + OFF)
    print()
    if not yes(f"write this to {str(path).replace(str(HOME), '~')}?"):
        return False
    b = backup(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new)
    ok("written" + (f" (old one: {str(b).replace(str(HOME), '~')})" if b else ""))
    return True


# ── screens ──────────────────────────────────────────────────────────────────
TURN = [(0, "upright"), (3, "turned right (portrait)"), (1, "turned left (portrait)"), (2, "upside down")]
KDE_TURN = {1: 0, 2: 1, 4: 2, 8: 3}  # kscreen rotation → Hyprland transform


def detect_screens():
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        r = run(["hyprctl", "monitors", "all", "-j"])
        if r and r.returncode == 0:
            out = []
            for m in json.loads(r.stdout):
                modes = []
                for s in m.get("availableModes", []):
                    mm = re.match(r"(\d+)x(\d+)@([\d.]+)", s)
                    if mm: modes.append((int(mm[1]), int(mm[2]), float(mm[3])))
                out.append({"name": m["name"], "desc": m.get("description", ""), "x": m["x"], "y": m["y"],
                            "w": m["width"], "h": m["height"], "hz": m["refreshRate"], "scale": m["scale"],
                            "transform": m["transform"], "modes": modes, "off": m.get("disabled", False)})
            return out
    if os.environ.get("XDG_CURRENT_DESKTOP", "").upper().find("KDE") >= 0 and shutil.which("kscreen-doctor"):
        r = run(["kscreen-doctor", "-j"], timeout=5)    # hangs outside Plasma, hence the timeout
        if r and r.returncode == 0:
            out = []
            for o in json.loads(r.stdout).get("outputs", []):
                if not o.get("connected"): continue
                modes = {m["id"]: m for m in o.get("modes", [])}
                cur = modes.get(o.get("currentModeId"), {})
                out.append({"name": o["name"], "desc": "", "x": o["pos"]["x"], "y": o["pos"]["y"],
                            "w": cur.get("size", {}).get("width", 0), "h": cur.get("size", {}).get("height", 0),
                            "hz": cur.get("refreshRate", 60), "scale": o.get("scale", 1),
                            "transform": KDE_TURN.get(o.get("rotation", 1), 0), "off": not o.get("enabled", True),
                            "modes": [(m["size"]["width"], m["size"]["height"], m["refreshRate"]) for m in modes.values()]})
            return out
    return []


def turn_label(t): return dict(TURN).get(t, f"transform {t}")


def hz(v): return f"{v:.2f}".rstrip("0").rstrip(".")


def monitor_block(screens):
    lines = ["-- screens, left to right (./nook setup screens wrote this)"]
    x = 0
    for s in screens:
        w, h = (s["h"], s["w"]) if s["transform"] in (1, 3) else (s["w"], s["h"])
        lw = round(w / s["scale"])
        extra = f", transform = {s['transform']}" if s["transform"] else ""
        lines.append(f"-- {s['name']}: {s['desc'] or 'screen'}, {turn_label(s['transform'])}")
        lines.append(f'hl.monitor({{ output = "{s["name"]}", mode = "{s["w"]}x{s["h"]}@{hz(s["hz"])}", '
                     f'position = "{x}x0", scale = {hz(s["scale"])}{extra} }})')
        x += lw
    return lines


def replace_monitors(text, block):
    """swap the fixed hl.monitor lines (and the comments right above them) for block; the
    catch-all line for other screens (output = "") stays"""
    lines = text.splitlines()
    keep, first = [], None
    i = 0
    while i < len(lines):
        l = lines[i]
        if l.strip().startswith("hl.monitor(") and 'output = ""' not in l:
            # drop the comment lines right above it
            while keep and keep[-1].strip().startswith("--") and not keep[-1].startswith("-- ──"):
                keep.pop()
            while keep and keep[-1].strip() == "" and keep[-2:-1] and keep[-2].strip() == "":
                keep.pop()
            if first is None: first = len(keep)
        else:
            keep.append(l)
        i += 1
    if first is None:   # no screens yet: after the header comment
        first = next((n for n, l in enumerate(keep) if not l.startswith("--")), len(keep))
    keep[first:first] = block + [""]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(keep)).rstrip("\n") + "\n"


def step_screens():
    screens = [s for s in detect_screens() if not s["off"]]
    if not screens:
        warn("can't see the screens from here (run this inside Hyprland or Plasma)")
        if yes(f"open {MACHINE} in an editor instead?", False):
            subprocess.call([os.environ.get("EDITOR", "nano"), str(MACHINE)])
        return
    screens.sort(key=lambda s: (s["x"], s["y"]))
    say("right now:")
    for i, s in enumerate(screens, 1):
        say(f"  {i}) {s['name']:<8} {s['w']}x{s['h']}@{hz(s['hz'])}  {turn_label(s['transform'])}  {dim(s['desc'])}")
    if len(screens) > 1:
        names = " ".join(s["name"] for s in screens)
        while True:
            order = ask("left to right (names or numbers)", names).replace(",", " ").split()
            pick = []
            for o in order:
                s = screens[int(o) - 1] if o.isdigit() and 0 < int(o) <= len(screens) else next((x for x in screens if x["name"] == o), None)
                if s and s not in pick: pick.append(s)
            if len(pick) == len(screens): screens = pick; break
            warn("name every screen once")
    for s in screens:
        print(f"\n  {LAV}{s['name']}{OFF} {dim(s['desc'])}")
        modes = sorted(set(s["modes"]), key=lambda m: (-m[0] * m[1], -m[2]))
        best = [m for m in modes if m[0] * m[1] == modes[0][0] * modes[0][1]][:5] if modes else []
        cur = (s["w"], s["h"], s["hz"])
        opts = [(cur, f"{cur[0]}x{cur[1]} @ {hz(cur[2])} Hz  (now)")]
        opts += [(m, f"{m[0]}x{m[1]} @ {hz(m[2])} Hz") for m in best if abs(m[2] - cur[2]) > 0.5 or m[:2] != cur[:2]]
        if len(opts) > 1:
            s["w"], s["h"], s["hz"] = choose("resolution and refresh rate", opts)
        s["transform"] = choose("which way up", TURN, [t for t, _ in TURN].index(s["transform"]) if s["transform"] in (0, 1, 2, 3) else 0)
        sc = ask("scale (1 = sharp, 1.25/1.5/2 = bigger)", hz(s["scale"]))
        try: s["scale"] = float(sc)
        except ValueError: warn("kept " + hz(s["scale"]))
    old = MACHINE.read_text() if MACHINE.exists() else (REPO / "tile/hypr/machine.lua").read_text()
    if write_checked(MACHINE, old, replace_monitors(old, monitor_block(screens))) and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        run(["hyprctl", "reload"])
        ok("Hyprland reloaded. Upside down? ./nook setup screens and pick the other side")


# ── keyboard ─────────────────────────────────────────────────────────────────
def xkb_layouts():
    try:
        txt = Path("/usr/share/X11/xkb/rules/evdev.lst").read_text()
    except OSError:
        return {}
    sec = txt.split("! layout", 1)[1].split("!", 1)[0]
    names = {l.split(None, 1)[0]: l.split(None, 1)[1].strip() for l in sec.splitlines() if l.strip()}
    # the "extra" layouts (EurKEY …) aren't in evdev.lst
    try:
        xml = Path("/usr/share/X11/xkb/rules/evdev.extras.xml").read_text()
        for code, desc in re.findall(r"<layout>\s*<configItem[^>]*>\s*<name>([^<]+)</name>.*?<description>([^<]+)</description>", xml, re.S):
            names.setdefault(code, desc)
    except OSError:
        pass
    return names


def step_keyboard():
    old = MACHINE.read_text() if MACHINE.exists() else (REPO / "tile/hypr/machine.lua").read_text()
    m = re.search(r'kb_layout\s*=\s*"([^"]*)"', old)
    cur = m[1] if m else "us"
    known = xkb_layouts()
    say("layouts by their xkb code, the first is the default; SUPER K (and the dot in the clock) switches.")
    say(dim("e.g. us · de · eu (EurKEY) · fr · gb · us,de"))
    while True:
        new = ",".join(ask("layouts", cur).replace(",", " ").split())   # "de eu" or "de, eu" too
        bad = [l for l in new.split(",") if not Path(f"/usr/share/X11/xkb/symbols/{l}").is_file()]
        if not bad and re.fullmatch(r"[a-z0-9_]+(,[a-z0-9_]+)*", new): break
        warn(f"unknown: {', '.join(bad) or new}")
    say(dim(" · ".join(f"{l} = {known.get(l, '?')}" for l in new.split(","))))
    if m:
        text = old[:m.start(1)] + new + old[m.end(1):]
        # the comment after it names the layouts
        names = " and ".join(known.get(l, l) for l in new.split(","))
        text = re.sub(r'(kb_layout\s*=\s*"[^"]*",?[ \t]*)--[^\n]*', lambda x: x[1] + f"-- {names}; SUPER K switches", text, count=1)
    else:
        text = old.rstrip("\n") + f'\n\nhl.config({{ input = {{ kb_layout = "{new}" }} }})\n'
    if write_checked(MACHINE, old, text) and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        run(["hyprctl", "reload"])


# ── widgets ──────────────────────────────────────────────────────────────────
def feed(*a):
    exe = shutil.which("nook-feed") or str(REPO / "tile/bin/nook-feed")
    return run([exe, *a])


def step_widgets():
    r = feed("conf")
    if not r or r.returncode:
        warn("nook-feed isn't working; is the tile shell part installed?")
        return
    conf = json.loads(r.stdout)
    loc = conf["weather"].get("location", "")
    say("WX // OUTSIDE: a city, a place like ~Eiffel Tower, an airport code; empty = found by your IP.")
    new = ask("weather place", loc or "by IP")
    if new != (loc or "by IP"):
        feed("set", "weather", "location", "" if new == "by IP" else new)
        ok("weather: " + new)
    say("SRV // HOMELAB pings your machines. name = host, or host:port for a TCP check.")
    for h in conf["srv"]:
        say(f"  {h['name']:<16} {h['host']}")
    while True:
        a = ask("add (name host), remove (-name), or ⏎ when done", "")
        if not a: break
        if a.startswith("-"):
            r = feed("unset", "srv", a[1:])
        else:
            parts = a.split()
            if len(parts) != 2: warn("name and host, e.g.  nas 192.168.1.10"); continue
            r = feed("set", "srv", *parts)
        print("  " + ((r.stdout or r.stderr).strip() if r else "nook-feed failed"))
    cal = conf["cal"]
    say("CAL // NEXT shows your next events from CalDAV (Nextcloud: https://<cloud>/remote.php/dav/calendars/<user>/).")
    if yes("set up the calendar?", not cal.get("url")):
        url = ask("CalDAV url", cal.get("url", ""))
        user = ask("user", cal.get("user", ""))
        if url: feed("set", "cal", "url", url)
        if user: feed("set", "cal", "user", user)
        if yes("store the password (an app password) in the keyring now?"):
            exe = shutil.which("nook-feed") or str(REPO / "tile/bin/nook-feed")
            subprocess.call([exe, "cal", "--setup"])
    ok("the widgets pick it up on their next refresh")


# ── shell ────────────────────────────────────────────────────────────────────
def step_shell():
    zsh = shutil.which("zsh")
    import pwd
    cur = pwd.getpwuid(os.getuid()).pw_shell
    if not zsh:
        warn("zsh isn't installed (./nook → shell → zsh)")
        return
    if os.path.basename(cur) == "zsh":
        ok(f"your login shell is already zsh ({cur})")
        return
    say(f"your login shell is {cur}. The nook terminals start zsh anyway; this makes it the")
    say("shell everywhere (tty, ssh in). It asks for your password.")
    if yes("make zsh your login shell?"):
        subprocess.call(["chsh", "-s", zsh])


# ── browser ──────────────────────────────────────────────────────────────────
BROWSERS = ["brave-browser", "com.brave.Browser", "google-chrome", "com.google.Chrome", "chromium",
            "chromium-browser", "org.chromium.Chromium", "firefox", "org.mozilla.firefox",
            "librewolf", "zen", "vivaldi-stable"]
CHROMIUM = ("brave", "chrome", "chromium", "vivaldi")


def step_browser():
    apps = [d for d in BROWSERS for base in (Path("/usr/share/applications"), HOME / ".local/share/applications",
            Path("/var/lib/flatpak/exports/share/applications")) if (base / f"{d}.desktop").exists()]
    apps = list(dict.fromkeys(apps))
    r = run(["xdg-settings", "get", "default-web-browser"])
    cur = r.stdout.strip().removesuffix(".desktop") if r and r.returncode == 0 else ""
    if apps:
        say(f"default browser: {cur or 'none'} (SUPER B goes to it)")
        new = choose("default browser", [(a, a + ("  (now)" if a == cur else "")) for a in apps],
                     apps.index(cur) if cur in apps else 0)
        if new != cur and run(["xdg-settings", "set", "default-web-browser", new + ".desktop"]):
            ok(f"default browser: {new}")
            cur = new
    if not any(c in cur for c in CHROMIUM):
        say(dim("the launcher's tabs need Brave, Chrome or Chromium; skipped"))
        return
    if "." in cur:
        warn("a Flatpak browser can't start nook-tabs (sandbox); the launcher's tabs need the system package")
        return
    ext = REPO / "tile/browser/nook-tabs"
    tabs = shutil.which("nook-tabs") or str(REPO / "tile/bin/nook-tabs")
    if run([tabs, "list"]) and run([tabs, "list"]).returncode == 0:
        ok("nook tabs is already connected")
        return
    say("Your tabs in the launcher (@ in SUPER SPACE) need the nook tabs extension, loaded once:")
    say(f"  1) open {LAV}brave://extensions{OFF} (chrome://extensions in Chrome)")
    say("  2) switch on Developer mode (top right)")
    say(f"  3) Load unpacked → {LAV}{ext}{OFF}")
    if shutil.which("wl-copy"):
        run(["wl-copy", str(ext)])
        say(dim("   (that folder is on your clipboard)"))
    say(dim("It can list, show and close tabs and nothing else; it only talks to bin/nook-tabs."))
    run([tabs, "install"])
    if not yes("done? (n skips)"): return
    for _ in range(10):
        r = run([tabs, "list"])
        if r and r.returncode == 0:
            ok(f"connected: {len(r.stdout.splitlines())} tabs")
            return
        time.sleep(1)
    warn("not connected yet. Restart the browser once; `nook-tabs list` should print your tabs")


# ── session ──────────────────────────────────────────────────────────────────
def step_session():
    if not Path("/usr/share/wayland-sessions/hyprland.desktop").exists():
        warn("no Hyprland session installed")
        return
    say("The login screen can preselect Hyprland, so you don't pick it every time (sudo).")
    say(dim("Plasma stays in the list; shared/login/default-session.sh plasma switches back."))
    if yes("preselect Hyprland?"):
        subprocess.call([str(REPO / "shared/login/default-session.sh"), "hyprland"])


# ── wled ─────────────────────────────────────────────────────────────────────
def step_wled():
    conf = REPO / "config/wled.conf"
    have = [l for l in conf.read_text().splitlines() if "|" in l and not l.startswith("#")] if conf.exists() else []
    say(f"config/wled.conf has {len(have)} devices.")
    if not yes("look for WLED controllers on your network (a few seconds)?"):
        return
    r = run([sys.executable, "-I", str(REPO / "shared/wled/wled.py"), "--scan"], timeout=60)
    found = [l.split()[0] for l in (r.stdout.splitlines() if r else []) if re.match(r"\d+\.\d+\.\d+\.\d+\s", l)]
    print("\n".join("   " + l for l in (r.stdout.splitlines() if r else [])))
    new = [ip for ip in found if not any(ip in l for l in have)]
    if not new:
        ok("nothing new")
        return
    if yes(f"add {len(new)} new to config/wled.conf?"):
        old = conf.read_text() if conf.exists() else "# WLED devices: name | address\n"
        n = len(have)
        add = "".join(f"wled-{n + i + 1} | {ip}\n" for i, ip in enumerate(new))
        write_checked(conf, old, old.rstrip("\n") + "\n" + add)


def main():
    a = sys.argv[1:]
    if a and a[0] in ("-h", "--help", "help"):
        print(__doc__.strip()); return
    steps = a or STEPS
    for s in steps:
        if s not in STEPS: sys.exit(f"unknown step {s} (have: {' '.join(STEPS)})")
    print(f"\n{MINT}λ{OFF} setup · {' · '.join(steps)}   {dim('⏎ default · s skip · q quit')}")
    for s in steps:
        print(f"\n{MINT}λ{OFF} {s}")
        try:
            globals()["step_" + s]()
        except Skip:
            say(dim("skipped"))
        except Quit:
            say(dim("setup ended; ./nook setup picks it up again"))
            return
        except KeyboardInterrupt:
            print(); say(dim("setup ended")); return
    print(f"\n{MINT}λ{OFF} setup done")


if __name__ == "__main__":
    main()
