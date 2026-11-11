#!/usr/bin/env python3
"""Previews for ./nook's TUI, drawn in truecolor for fzf's preview pane.

usage: preview.py palette NAME          swatches, a bar, a prompt and icons in that palette
       preview.py desktop plasma|tile   what the desktop looks like (drawn in its palette)
       preview.py shell ITEM            what a shell part does, with an example
       preview.py plan FILE             the summary before installing (FILE: key=value lines)
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTES = ROOT / "palettes"
RESET = "\x1b[0m"


def load(name):
    p = json.loads((PALETTES / f"{name}.json").read_text())
    r = dict(p["roles"])
    for k, v in p.get("aliases", {}).items():
        r.setdefault(k, r[v])
    p["r"] = r
    return p


def fg(h): h = h.lstrip("#"); return f"\x1b[38;2;{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}m"
def bg(h): h = h.lstrip("#"); return f"\x1b[48;2;{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}m"
def c(h, s): return fg(h) + s + RESET
def on(b, f, s): return bg(b) + fg(f) + s + RESET


HUES = ["media", "danger", "time", "files", "dev", "comms", "net", "system", "session"]
CATEGORY = {"media": "music, video", "danger": "lock, errors", "time": "clock, downloads",
            "files": "folders, docs", "dev": "code, shell", "comms": "chat, mail",
            "net": "browser, wifi", "system": "settings, cpu", "session": "user, power"}


def palette(name):
    p = load(name)
    r = p["r"]
    out = []
    out.append(c(r["ink"], f" {p['title']}") + c(r["faint"], f"  ·  palettes/{name}.json"))
    out.append(c(r["muted"], f" {p['description']}"))
    out.append("")
    # grounds and text
    out.append(" " + "".join(on(r[k], r["ink"], f" {k} ") for k in ("bg000", "bg100", "bg200", "bg300")))
    out.append(" " + on(r["bg100"], r["ink"], " ink ") + on(r["bg100"], r["muted"], " muted ")
               + on(r["bg100"], r["faint"], " faint ") + on(r["bg100"], r["line"], " line ")
               + on(r["focus"], r["bg100"], " focus ") + on(r["accent"], r["bg100"], " accent "))
    out.append("")
    # the nine hues, one per category
    for h in HUES:
        out.append(" " + on(r[h], r["bg100"], "    ") + " " + c(r[h], f"{h:<8}") + c(r["faint"], CATEGORY[h]))
    out.append("")
    # a bar like nook-tile's
    pill = lambda s, col=None: on(r["bg100"], col or r["muted"], f" {s} ")
    out.append(" " + on(r["accent"], r["bg100"], " λ nook ") + " "
               + pill(c(r["focus"], "▬▬") + bg(r["bg100"]) + fg(r["faint"]) + " ■ ■ ■") + " "
               + pill("14:32", r["accent"]) + " " + pill("cpu ⣀⣤⣶ 12%", r["system"]) + " "
               + on(r["accent"], r["bg100"], " ⏻ "))
    out.append("")
    # a prompt and some ls output
    out.append(" " + on(r["bg000"], r["line"], "╭─[") + on(r["bg000"], r["accent"], "λ ")
               + on(r["bg000"], r["session"], "nbax") + on(r["bg000"], r["faint"], "@")
               + on(r["bg000"], r["focus"], "nook") + on(r["bg000"], r["line"], "]─[")
               + on(r["bg000"], r["net"], "~/proj") + on(r["bg000"], r["line"], "]─[")
               + on(r["bg000"], r["faint"], "git:") + on(r["bg000"], r["session"], "main")
               + on(r["bg000"], r["files"], " ●2") + on(r["bg000"], r["line"], "]   "))
    out.append(" " + on(r["bg000"], r["line"], "╰─") + on(r["bg000"], r["accent"], "▶ ")
               + on(r["bg000"], r["dev"], "ls ") + on(r["bg000"], r["muted"], "-la                          "))
    out.append(" " + on(r["bg000"], r["net"], "src/  ") + on(r["bg000"], r["net"], "docs/  ")
               + on(r["bg000"], r["dev"], "run.sh  ") + on(r["bg000"], r["ink"], "README.md  ")
               + on(r["bg000"], r["session"], "nook.zip       "))
    out.append("")
    # icons, one colour per category
    icons = [("▤", "files", "folder"), ("♫", "media", "music"), ("</>", "dev", "code"), ("◉", "net", "web"),
             ("✉", "comms", "chat"), ("⚙", "system", "settings"), ("⚿", "danger", "lock"), ("◷", "time", "clock")]
    out.append(" " + "  ".join(c(r[k], g) for g, k, _ in icons))
    out.append(" " + c(r["faint"], "icons: one colour per category"))
    return "\n".join(out)


def desktop(kind, pal):
    r = load(pal)["r"]
    D = lambda s: on(r["bg000"], r["dots"], s)
    out = []
    if kind == "plasma":
        out.append(c(r["ink"], " Plasma rice") + c(r["faint"], "  ·  KDE Plasma 6 + Krohnkite tiling"))
        out.append(c(r["muted"], " floating cocoa/neon taskbar, desktop widgets, key cheat-sheet"))
        out.append(c(r["muted"], " on the wallpaper, own icons, cursor, window frames, logout screen"))
        out.append("")
        w = 46
        out.append(" " + D("·" * w))
        out.append(" " + D("· ") + on(r["bg100"], r["focus"], " TIME // LOCAL ") + D(" ") + on(r["bg100"], r["focus"], " KEYS // CHEATSHEET   ") + D("  ·"))
        out.append(" " + D("· ") + on(r["bg100"], r["accent"], "  ## ##:## ##  ") + D(" ") + on(r["bg100"], r["muted"], " Meta+⏎ terminal      ") + D("  ·"))
        out.append(" " + D("· ") + on(r["bg100"], r["system"], " SYS // LIVE   ") + D(" ") + on(r["bg100"], r["muted"], " Meta+E files         ") + D("  ·"))
        out.append(" " + D("· ") + on(r["bg100"], r["dev"], " cpu [████░░]  ") + D(" " * 24) + D("  ·"))
        out.append(" " + D("·" * 30) + c(r["media"], "N") + c(r["time"], "O") + c(r["dev"], "O") + c(r["net"], "K") + D("·" * 12))
        out.append(" " + on(r["bg100"], r["session"], " ⬡λ ") + on(r["bg100"], r["muted"], " ▣ ▣ ▣ ▣   ")
                   + on(r["bg100"], r["accent"], " 16:34 ") + on(r["bg100"], r["faint"], " fri 09.10   ") + on(r["bg100"], r["muted"], " ⌂ ♪ ▲ ^  "))
        out.append("")
        out.append(c(r["faint"], " needs a Plasma session: started from Hyprland it runs at the next Plasma login"))
    else:
        out.append(c(r["ink"], " nook-tile") + c(r["faint"], "  ·  Hyprland 0.57 + Quickshell"))
        out.append(c(r["muted"], " tiling with a rotating neon border, floating bar, hack-menu launcher,"))
        out.append(c(r["muted"], " control center (sound, wifi, bt), cheatsheet on the wallpaper, gaming"))
        out.append("")
        b = lambda s, col: on(r["bg200"], col, s)
        out.append(" " + c(r["focus"], "┏" + "━" * 24 + "┓") + " " + c(r["line"], "┌" + "─" * 17 + "┐"))
        out.append(" " + c(r["focus"], "┃") + b(" kitty — ~/proj        ", r["focus"]) + c(r["accent"], "┃") + " " + c(r["line"], "│") + b(" btop            ", r["system"]) + c(r["line"], "│"))
        out.append(" " + c(r["focus"], "┃") + b(" λ ~/ > nook          ", r["dev"]) + b(" ", r["ink"]) + c(r["accent"], "┃") + " " + c(r["line"], "│") + b(" cpu ⣀⣤⣶⣿       ", r["system"]) + c(r["line"], "│"))
        out.append(" " + c(r["accent"], "┗" + "━" * 24 + "┛") + " " + c(r["line"], "└" + "─" * 17 + "┘"))
        out.append(" " + on(r["accent"], r["bg100"], " λ nook ") + on(r["bg100"], r["focus"], " ▬▬ ■ ■ ")
                   + on(r["bg100"], r["accent"], " 15:23 ") + on(r["bg100"], r["muted"], " sa 08.11 ")
                   + on(r["bg100"], r["net"], " net ▂▄▆ ") + on(r["accent"], r["bg100"], " ⏻ "))
        out.append("")
        out.append(c(r["faint"], " Fedora/Nobara 44+ or Ubuntu 26.04+ (Hyprland ≥ 0.57 from COPR / PPA)"))
    return "\n".join(out)


SHELL = {
    "zsh": ("zsh", "zsh in the nook terminals (kitty, Konsole's Nook profile)", "chsh is left alone"),
    "omz": ("oh-my-zsh", "autosuggestions (grey ghost text) and syntax highlighting in the palette", "git ↹ → git checkout …"),
    "prompt-nook": ("prompt · nook", "two lines from the oh-my-zsh theme", "╭─λ nbax@nook ─ ~/proj ─  main ✓\n ╰─❯"),
    "prompt-starship": ("prompt · starship", "bracketed tags, duration, exit code, time (needs starship)", "╭─[λ nbax@nook]─[~/proj]─[git:main ●2]\n ╰─▶                 took 4s · 14:55"),
    "prompt-plain": ("prompt · plain", "one short line, no extras", "λ ~/proj ›"),
    "zoxide": ("zoxide", "cd learns where you go: `cd proj` jumps to ~/code/proj, `cdi` picks with fzf", "cd kde → ~/proj/kde-rice"),
    "eza": ("eza", "ls with colours, git status and dirs first; ll, la, lt (tree)", "ll → drwxr-xr-x  -  2h  src/  M"),
    "bat": ("bat", "cat with syntax highlighting, coloured man pages, fzf preview", "cat main.py → highlighted, numbered"),
    "delta": ("delta", "git diffs side by side with syntax colours", "git diff → word-level highlights"),
    "fd": ("fd", "fast find; feeds fzf's Ctrl+T and Alt+C", "fd conf → every *conf* path"),
    "ripgrep": ("ripgrep", "rg: fast grep with smart case and palette colours", "rg TODO"),
    "fzf": ("fzf", "Ctrl+R history, Ctrl+T files, Alt+C dirs, in the palette", "Ctrl+R → λ fuzzy history"),
    "fastfetch": ("fastfetch", "system info once per new nook terminal", "the mug (Plasma) or the axolotl (tile)"),
    "btop": ("btop", "system monitor with the nook theme", "SUPER ⇧ ⏎ in nook-tile"),
    "cava": ("cava", "audio visualiser bars in the palette", ""),
    "git": ("git colours", "status, branch and diff colours; git lg, git st, git last", "git lg → one-line graph"),
    "yazi": ("yazi", "terminal file manager with previews; `y` opens it and leaves you where you quit", "y → ~/proj, q → cd ~/proj/nook"),
    "lazygit": ("lazygit", "git in a TUI: stage lines, rebase, cherry-pick; `lg`", "lg → status · branches · log"),
    "tldr": ("tldr (tealdeer)", "short examples instead of the whole man page", "tldr tar → the five tar lines you need"),
    "direnv": ("direnv", "a folder's .envrc loads when you cd in, unloads when you leave", "cd proj → venv + API keys loaded"),
    "dust": ("dust", "du as a tree of bars: what eats the disk", "dust ~ → .cache 12G ████"),
    "duf": ("duf", "df as a table: every disk, how full", "duf → /  71% ███████░░░"),
    "glow": ("glow", "markdown rendered in the terminal; `md FILE`", "md README.md"),
    "opencode": ("opencode", "coding agent in the terminal, any provider (Anthropic, OpenAI, OpenRouter, Ollama, free models); `oc`", "oc → Build · plan · subagents, in the palette"),
}


def shell(item, pal):
    r = load(pal)["r"]
    name, what, ex = SHELL.get(item, (item, "", ""))
    out = [c(r["accent"], " " + name), "", c(r["ink"], " " + what)]
    if ex:
        out += ["", c(r["faint"], " example"), " " + c(r["dev"], ex.replace("\n", "\n" + fg(r["dev"])))]
    return "\n".join(out)


def plan(path, pal):
    r = load(pal)["r"]
    kv = dict(l.split("=", 1) for l in Path(path).read_text().splitlines() if "=" in l)
    row = lambda k, v, col: c(r["faint"], f" {k:<10}") + c(col, v)
    yes = lambda k: kv.get(k) == "1"
    out = [c(r["ink"], " what ./nook will do"), ""]
    out.append(row("plasma", f"yes · {kv.get('plasma_palette')}" if yes("plasma") else "no", r["focus"] if yes("plasma") else r["faint"]))
    out.append(row("tile", f"yes · {kv.get('tile_palette')}" if yes("tile") else "no", r["focus"] if yes("tile") else r["faint"]))
    out.append(row("shell", (f"{kv.get('shell_palette')} · " + kv.get("shell", "").replace(",", " ")) if yes("shell_on") else "no", r["focus"] if yes("shell_on") else r["faint"]))
    out.append(row("login", f"yes · {kv.get('login_palette')}" if yes("login") else "no", r["focus"] if yes("login") else r["faint"]))
    out.append(row("wled", "glow presets" if yes("wled") else "no", r["focus"] if yes("wled") else r["faint"]))
    out.append(row("packages", "yes (sudo)" if yes("deps") else "no", r["accent"] if yes("deps") else r["faint"]))
    out.append("")
    out.append(c(r["faint"], " runs:"))
    for line in kv.get("cmds", "").split(";;"):
        if line.strip():
            out.append(" " + c(r["dev"], "λ ") + c(r["muted"], line.strip()))
    return "\n".join(out)


def main():
    a = sys.argv[1:]
    pal = (a[2] if len(a) > 2 else None) or "ramen"
    if a[0] == "palette": print(palette(a[1]))
    elif a[0] == "desktop": print(desktop(a[1], pal))
    elif a[0] == "shell": print(shell(a[1], pal))
    elif a[0] == "plan": print(plan(a[1], pal))


if __name__ == "__main__":
    main()
