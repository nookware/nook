#!/usr/bin/env python3
"""Write an OpenCode v2 theme (~/.config/opencode/themes/nook.json) from a Nook palette.

usage: opencode_theme.py PALETTE [OUT]     (palettes/PALETTE.json; OUT defaults to stdout)

OpenCode v2 themes are a token tree: `base` holds every token, `dark` the hue ramps
(100 = lightest … 900 = darkest) that `$hue.<name>.<step>` references resolve against.
The ramps are mixed from the palette towards white and towards its darkest ground, so the
theme follows any palette instead of being recoloured hex by hex.
"""
import json
import sys
from pathlib import Path

PALETTES = Path(__file__).resolve().parent.parent / "palettes"
STEPS = (100, 200, 300, 400, 500, 600, 700, 800, 900)


def load(name):
    p = json.loads((PALETTES / f"{name}.json").read_text())
    r = dict(p["roles"])
    for k, v in p.get("aliases", {}).items():
        r.setdefault(k, r[v])
    return r, p["ansi"]


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def mix(a, b, t):  # t=0 → a, t=1 → b
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(rgb(a), rgb(b)))


def ramp(c, dark):
    """200 is the palette colour itself; lighter above, sinking into the ground below."""
    ts = {100: -0.35, 200: 0, 300: 0.18, 400: 0.34, 500: 0.5, 600: 0.64, 700: 0.76, 800: 0.86, 900: 0.93}
    return {str(s): (mix(c, "#ffffff", -t) if t < 0 else mix(c, dark, t)) for s, t in ts.items()}


def theme(name):
    r, ansi = load(name)
    bg = r["bg000"]
    neutral = dict(zip(map(str, STEPS), [
        mix(r["ink"], "#ffffff", 0.5), r["ink"], mix(r["ink"], r["muted"], 0.5), r["muted"],
        r["faint"], r["line"], r["bg300"], r["bg200"], r["bg100"]]))
    hue = {
        "gray": neutral,
        # the terminal's own six colours, so OpenCode reads like the rest of the shell
        "red": ramp(ansi[1], bg), "green": ramp(ansi[2], bg), "yellow": ramp(ansi[3], bg),
        "blue": ramp(ansi[4], bg), "purple": ramp(ansi[5], bg), "cyan": ramp(ansi[6], bg),
        "accentc": ramp(r["accent"], bg), "focusc": ramp(r["focus"], bg),
        "accent": "$hue.accentc", "interactive": "$hue.focusc", "neutral": "$hue.gray",
    }
    over = lambda c, t: mix(c, bg, t)  # a colour sunk into the ground, for diff backgrounds
    act = lambda base, **kw: {"base": base, **{"$" + k: v for k, v in kw.items()}}
    base = {
        "categorical": ["accentc", "focusc", "green", "yellow", "blue", "purple", "cyan", "red"],
        "text": {
            "base": r["ink"], "muted": r["muted"], "faint": r["faint"],
            "action": {
                "primary": act("$text.base", disabled=r["faint"], focused="$hue.interactive.200", selected="$hue.interactive.200"),
                "secondary": act("$text.muted", hovered="$text.base"),
                "destructive": act(ansi[1], disabled=r["faint"]),
            },
            "formfield": act(r["ink"], hovered="$hue.interactive.200", focused="$hue.interactive.200",
                             pressed="$hue.interactive.200", disabled=r["faint"], selected="$hue.interactive.200"),
            "feedback": {"error": {"base": ansi[1]}, "warning": {"base": ansi[3]},
                         "success": {"base": ansi[2]}, "info": {"base": r["focus"]}},
        },
        "background": {
            # transparent: the terminal's own (kitty / Konsole) Nook background shows through
            "base": "transparent",
            "raised": {"base": r["bg200"], "high": r["bg300"], "max": r["line"]},
            "action": {
                "primary": act("transparent", hovered=r["bg300"], focused="$hue.interactive.800", selected="transparent"),
                "secondary": act("transparent"),
                "destructive": act(ansi[1]),
            },
            "formfield": act("$background.raised.base"),
            "feedback": {k: {"base": "$background.base"} for k in ("error", "warning", "success", "info")},
        },
        "border": {"base": r["line"]},
        "scrollbar": {"base": r["faint"]},
        "diff": {
            "text": {"added": ansi[2], "removed": ansi[1], "context": r["muted"], "hunkHeader": r["focus"]},
            "background": {"added": over(ansi[2], 0.84), "removed": over(ansi[1], 0.84), "context": "transparent"},
            "highlight": {"added": over(ansi[2], 0.62), "removed": over(ansi[1], 0.62)},
            "lineNumber": {"text": r["faint"], "background": {"added": over(ansi[2], 0.9), "removed": over(ansi[1], 0.9)}},
        },
        "syntax": {
            "comment": r["faint"], "keyword": r["focus"], "function": ansi[4], "variable": r["ink"],
            "string": ansi[2], "number": ansi[3], "type": ansi[5], "operator": r["muted"], "punctuation": r["muted"],
        },
        "markdown": {
            "text": r["ink"], "heading": r["accent"], "link": r["focus"], "linkText": ansi[4], "code": ansi[2],
            "blockQuote": r["muted"], "emphasis": ansi[3], "strong": r["ink"], "horizontalRule": r["line"],
            "listItem": r["focus"], "listEnumeration": r["focus"], "image": ansi[5], "imageText": r["muted"],
            "codeBlock": r["ink"],
        },
        "@dialog": {"background": {"base": r["bg200"], "action": {"primary": {"$hovered": r["bg300"]}}}},
    }
    return {"base": base, "dark": {"hue": hue}}


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = json.dumps(theme(sys.argv[1]), indent=2) + "\n"
    if len(sys.argv) > 2:
        Path(sys.argv[2]).parent.mkdir(parents=True, exist_ok=True)
        Path(sys.argv[2]).write_text(out)
    else:
        sys.stdout.write(out)
