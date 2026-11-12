#!/usr/bin/env python3
"""Nook-Pixel: an old-school 1-bit cursor theme (Win95 / Mac classic), drawn as pixel art and
scaled with hard edges. Writes Xcursor files directly (no xcursorgen, no Pillow).

usage: pixelcursors.py [DEST]                     Nook-Pixel (default DEST ~/.local/share/icons/Nook-Pixel)
       pixelcursors.py --style=Neon [DEST]        one glowing style: Halo, Neon, Ember, Dusk, Sign
       pixelcursors.py --all [ICONS_DIR]          every style as Nook-<Style>
       pixelcursors.py --sheet preview.png        a preview of every style (ImageMagick)
       --palette=NAME                             the glow colours from palettes/NAME.json (ramen)

Shapes are drawn as FILL only: 'o' = white (ink), 'y' = orange sand, 'r' = red, '#' = black.
A 1px black outline is added around every filled pixel automatically, so the classic look
(white body, black border) comes for free. '@' marks the hotspot (and is filled white).
"""
import os
import struct
import sys

INK, BLACK, SAND, RED = 0xFFF2F2F2, 0xFF060606, 0xFFFF9A3C, 0xFFFF6458
COLOURS = {"o": INK, "@": INK, "y": SAND, "r": RED, "#": BLACK}

SHAPES = {
    "default": """
@
oo
ooo
oooo
ooooo
oooooo
ooooooo
oooooooo
ooooooooo
oooooooooo
oooooo
ooo.oo
oo..oo
o....oo
.....oo
......oo
......oo
""",
    "pointer": """
....oo
....oo
....oo
....oo
....oo
....oo#oo#oo
....oo#oo#oo#o
.oo.oo#oo#oo#oo
.ooooooooooooooo
..ooooooooooooo
...oooooooooooo
...ooooooooooo
....oooooooooo
....oooooooooo
.....oooooooo
.....oooooooo
""",
    "text": """
ooo.ooo
...o...
...o...
...o...
...o...
...@...
...o...
...o...
...o...
...o...
...o...
ooo.ooo
""",
    "wait": """
ooooooooooo
.ooooooooo.
.oyyyyyyyo.
..oyyyyyo..
...oyyyo...
....o@o....
....oyo....
...ooyoo...
..ooyyyoo..
.oyyyyyyyo.
.ooooooooo.
ooooooooooo
""",
    "crosshair": """
......o......
......o......
......o......
......o......
......o......
.............
oooooo@oooooo
.............
......o......
......o......
......o......
......o......
......o......
""",
    "not-allowed": """
....rrrrr....
..rrrrrrrrr..
.rrr.....rrr.
.rrrr.....rr.
rr.rrr.....rr
rr..rrr....rr
rr...r@r...rr
rr....rrr..rr
rr.....rrr.rr
.rr.....rrrr.
.rrr.....rrr.
..rrrrrrrrr..
....rrrrr....
""",
    "move": """
......o......
.....ooo.....
....ooooo....
......o......
..o...o...o..
.oo...o...oo.
oooooo@oooooo
.oo...o...oo.
..o...o...o..
......o......
....ooooo....
.....ooo.....
......o......
""",
    "ew-resize": """
...o.......o...
..oo.......oo..
.ooooooooooooo.
ooooooo@ooooooo
.ooooooooooooo.
..oo.......oo..
...o.......o...
""",
    "ns-resize": """
...o...
..ooo..
.ooooo.
ooooooo
..ooo..
..ooo..
..ooo..
..o@o..
..ooo..
..ooo..
..ooo..
ooooooo
.ooooo.
..ooo..
...o...
""",
    "nwse-resize": """
oooooo.....
ooooo......
oooo.......
ooooo......
oo.ooo.....
o...o@o...o
.....ooo.oo
......ooooo
.......oooo
......ooooo
.....oooooo
""",
}
SHAPES["nesw-resize"] = "\n".join(r[::-1] for r in SHAPES["nwse-resize"].strip("\n").split("\n"))

# every X / CSS cursor name → shape
NAMES = {
    "default": ["default", "left_ptr", "arrow", "top_left_arrow", "context-menu", "help", "question_arrow",
                "copy", "alias", "dnd-copy", "dnd-link", "dnd-move", "dnd-none", "cell", "vertical-text", "zoom-in", "zoom-out",
                "left_ptr_help", "whats_this", "progress", "left_ptr_watch", "half-busy", "00000000000000020006000e7e9ffc3f",
                "08e8e1c95fe2fc01f976f1e063a24ccd", "3ecb610c1bf2410f44200f48c40d3599", "d9ce0ab605698f320427677b458ad60b"],
    "pointer": ["pointer", "hand1", "hand2", "pointing_hand", "grab", "openhand", "grabbing", "closedhand",
                "e29285e634086352946a0e7090d73106", "9d800788f1b08800ae810202380a0822"],
    "text": ["text", "xterm", "ibeam"],
    "wait": ["wait", "watch"],
    "crosshair": ["crosshair", "cross", "tcross", "cross_reverse", "diamond_cross", "plus", "color-picker"],
    "not-allowed": ["not-allowed", "crossed_circle", "forbidden", "no-drop", "circle", "03b6e0fcb3499374a867c041f52298f0"],
    "move": ["move", "fleur", "all-scroll", "size_all", "4498f0e0c1937ffe01fd06f973665830", "9081237383d90e509aa00f00170e968f"],
    "ew-resize": ["ew-resize", "col-resize", "e-resize", "w-resize", "sb_h_double_arrow", "h_double_arrow",
                  "left_side", "right_side", "size_hor", "split_h", "14fef782d02440884392942c11205230", "028006030e0e7ebffc7f7070c0600140"],
    "ns-resize": ["ns-resize", "row-resize", "n-resize", "s-resize", "sb_v_double_arrow", "v_double_arrow",
                  "top_side", "bottom_side", "size_ver", "split_v", "2870a09082c103050810ffdffffe0204", "00008160000006810000408080010102"],
    "nwse-resize": ["nwse-resize", "nw-resize", "se-resize", "top_left_corner", "bottom_right_corner",
                    "size_fdiag", "bd_double_arrow", "c7088f0f3e6c8088236ef8e1e3e70000"],
    "nesw-resize": ["nesw-resize", "ne-resize", "sw-resize", "top_right_corner", "bottom_left_corner",
                    "size_bdiag", "fd_double_arrow", "fcf1c3c7cd4491d801f1e1c78f100000"],
}

# nominal size → pixel scale (hard edges)
SIZES = {16: 1, 20: 1.5, 24: 2, 32: 2, 48: 3, 64: 4, 96: 6}     # 1.5: nearest pixel, still hard-edged


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def argb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


# ── styles: the same pixel shapes, painted and lit differently ──────────────────────────────────
# body   the fill ('o')            line  the 1px outline (a colour, or (top, bottom) for a gradient)
# y / r  the two accent fills     glow  None, or (radius in shape pixels, gain, tint or None)
#        a tint lights the glow in one colour; without one every lit pixel glows in its own colour
def styles(roles):
    c = lambda k: rgb(roles[k])
    dark, ink, cyan, red = c("bg100"), c("ink"), c("focus"), c("time")
    gold, orange = c("files"), c("danger")
    return {
        "Pixel": dict(body=argb(INK), line=argb(BLACK), y=argb(SAND), r=argb(RED), glow=None,
                      comment="Old-school pixel cursors for nook (Win95 / Mac classic)"),
        "Halo":  dict(body=ink, line=c("bg000"), y=gold, r=orange, glow=(2.0, 1.1, cyan),
                      comment="The pixel cursors with the bar's cyan halo"),
        "Neon":  dict(body=dark, line=cyan, y=gold, r=orange, glow=(1.6, 1.6, None),
                      comment="A neon-tube outline in the focus cyan, glowing"),
        "Ember": dict(body=dark, line=red, y=gold, r=orange, glow=(1.6, 1.6, None),
                      comment="A neon-tube outline in the accent red, glowing"),
        "Dusk":  dict(body=dark, line=(cyan, red), y=gold, r=orange, glow=(1.6, 1.6, None),
                      comment="Neon tube turning cyan to red, like the window border"),
        "Sign":  dict(body=cyan, line=c("bg000"), y=gold, r=orange, glow=(2.4, 0.9, None),
                      comment="A solid lit sign in cyan, softly glowing"),
    }


def parse(art, st):
    """→ grid of (r, g, b) or None at shape resolution (outline included), the hotspot, lit mask."""
    rows = art.strip("\n").split("\n")
    w = max(len(r) for r in rows) + 2           # 1px border each side for the outline
    h = len(rows) + 2
    fills = {"o": st["body"], "@": st["body"], "y": st["y"], "r": st["r"], "#": None}
    grid = [[None] * w for _ in range(h)]
    kind = [[""] * w for _ in range(h)]
    hot = (1, 1)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in fills:
                grid[y + 1][x + 1] = fills[ch] if ch != "#" else st["line"] if isinstance(st["line"][0], int) else st["line"][0]
                kind[y + 1][x + 1] = "line" if ch == "#" else "accent" if ch in "yr" else "body"
            if ch == "@":
                hot = (x + 1, y + 1)
    line = st["line"]
    for y in range(h):
        col = line if isinstance(line[0], int) else tuple(round(a + (b - a) * y / (h - 1)) for a, b in zip(*line))
        for x in range(w):
            if kind[y][x] == "line":
                grid[y][x] = col
            if kind[y][x]:
                continue
            near = {kind[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                    if 0 <= y + dy < h and 0 <= x + dx < w}
            if "body" in near:
                grid[y][x], kind[y][x] = col, "edge"
            elif "accent" in near:                  # coloured signs keep a dark rim, not the neon line
                grid[y][x], kind[y][x] = st.get("rim", argb(BLACK)), "rim"
    return grid, kind, hot


def blur(ch, w, h, r):
    """three box blurs ≈ a gaussian; ch is a flat list of floats."""
    for _ in range(3):
        for horiz in (True, False):
            n, m = (w, h) if horiz else (h, w)
            out = [0.0] * len(ch)
            for j in range(m):
                idx = (lambda i: j * w + i) if horiz else (lambda i: i * w + j)
                acc, k = 0.0, 2 * r + 1
                line = [ch[idx(i)] for i in range(n)]
                for i in range(-r, r + 1):
                    acc += line[i] if 0 <= i < n else 0.0
                for i in range(n):
                    out[idx(i)] = acc / k
                    a, b = i + r + 1, i - r
                    acc += (line[a] if a < n else 0.0) - (line[b] if b >= 0 else 0.0)
            ch = out
    return ch


def render(grid, kind, hot, s, st):
    """→ (w, h, xhot, yhot, premultiplied ARGB pixels) at pixel scale s, glow included."""
    glow = st["glow"]
    pad = 0 if not glow else int(glow[0] * s * 2.2) + 1
    gh, gw = len(grid), len(grid[0])
    sw, sh = round(gw * s), round(gh * s)
    W, H = sw + 2 * pad, sh + 2 * pad
    sharp = [None] * (W * H)
    for y in range(sh):
        row = grid[int(y / s)]
        for x in range(sw):
            sharp[(y + pad) * W + x + pad] = row[int(x / s)]
    out = []
    if glow:
        radius, gain, tint = glow
        lit = [[None] * gw for _ in range(gh)]
        for y in range(gh):
            for x in range(gw):
                k = kind[y][x]
                if grid[y][x] is None or k in ("", "rim"):
                    continue
                if tint:
                    lit[y][x] = tint
                elif st["body"] != grid[y][x] or k == "accent" or k != "body" or sum(st["body"]) > 200:
                    lit[y][x] = grid[y][x]
        ca, cr, cg, cb = ([0.0] * (W * H) for _ in range(4))
        for y in range(sh):
            for x in range(sw):
                v = lit[int(y / s)][int(x / s)]
                if v:
                    i = (y + pad) * W + x + pad
                    ca[i], cr[i], cg[i], cb[i] = 1.0, v[0] / 255, v[1] / 255, v[2] / 255
        r = max(1, round(radius * s / 1.7))
        ca, cr, cg, cb = (blur(c, W, H, r) for c in (ca, cr, cg, cb))
    for i, v in enumerate(sharp):
        if v is not None:
            out.append(0xFF000000 | v[0] << 16 | v[1] << 8 | v[2])
        elif glow and ca[i] > 0.004:
            a = min(1.0, ca[i] * gain)
            f = a / ca[i]                       # scale the premultiplied colour with the alpha
            px = [min(255, round(c * f * 255)) for c in (cr[i], cg[i], cb[i])]
            out.append(round(a * 255) << 24 | px[0] << 16 | px[1] << 8 | px[2])
        else:
            out.append(0)
    return W, H, int((hot[0] + 0.5) * s) + pad, int((hot[1] + 0.5) * s) + pad, out


def xcursor(images):
    """images: list of (nominal, w, h, xhot, yhot, premultiplied ARGB). Returns Xcursor file bytes."""
    ntoc = len(images)
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, ntoc)
    pos = 16 + ntoc * 12
    toc, chunks = b"", b""
    for nominal, w, h, xh, yh, pix in images:
        chunk = struct.pack("<IIIIIIIII", 36, 0xFFFD0002, nominal, 1, w, h, xh, yh, 0)
        chunk += struct.pack("<%dI" % len(pix), *pix)
        toc += struct.pack("<III", 0xFFFD0002, nominal, pos)
        chunks += chunk
        pos += len(chunk)
    return header + toc + chunks


def write_theme(dest, name, st, sizes=SIZES):
    cdir = os.path.join(dest, "cursors")
    os.makedirs(cdir, exist_ok=True)
    for shape, art in SHAPES.items():
        grid, kind, hot = parse(art, st)
        data = xcursor([(n, *render(grid, kind, hot, s, st)) for n, s in sizes.items()])
        first, *aliases = NAMES[shape]
        with open(os.path.join(cdir, first), "wb") as f:
            f.write(data)
        for a in aliases:
            p = os.path.join(cdir, a)
            if os.path.lexists(p):
                os.remove(p)
            os.symlink(first, p)
    with open(os.path.join(dest, "index.theme"), "w") as f:
        f.write(f"[Icon Theme]\nName={name}\nComment={st['comment']}\n")


def sheet(path, sts, scale=3):
    """a preview PNG: one row per style, every shape, on dark and light ground (needs ImageMagick)."""
    import subprocess
    cell, rows = int(26 * scale) + 40, []
    W = cell * len(SHAPES)
    for name, st in sts.items():
        for ground in ((13, 13, 13), (232, 232, 232)):
            buf = bytearray(ground * (W * cell))
            for n, art in enumerate(SHAPES.values()):
                w, h, _, _, pix = render(*parse(art, st), scale, st)
                ox, oy = n * cell + (cell - w) // 2, (cell - h) // 2
                for y in range(h):
                    for x in range(w):
                        v = pix[y * w + x]
                        a = (v >> 24) / 255
                        if not a:
                            continue
                        i = ((oy + y) * W + ox + x) * 3
                        for k, sh in enumerate((16, 8, 0)):
                            buf[i + k] = min(255, round(((v >> sh) & 255) + buf[i + k] * (1 - a)))
            rows.append((name, bytes(buf)))
    raw = b"".join(b for _, b in rows)
    subprocess.run(["magick", "-size", f"{W}x{cell * len(rows)}", "-depth", "8", "rgb:-",
                    "(", "-size", f"140x{cell * len(rows)}", "xc:#0d0d0d", "-fill", "#f2f2f2",
                    "-font", subprocess.run(["fc-match", "-f", "%{file}", "JetBrains Mono"], capture_output=True, text=True).stdout, "-pointsize", "22",
                    *sum((["-annotate", f"+12+{i * 2 * cell + cell // 2 + 8}", n] for i, n in enumerate(sts)), []),
                    ")", "+swap", "+append", path], input=raw, check=True)


def main():
    import argparse
    import json
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dest", nargs="?", help="theme dir (one style) or parent dir (--all)")
    ap.add_argument("--style", default="Pixel")
    ap.add_argument("--all", action="store_true", help="write every style as Nook-<Style> into DEST")
    ap.add_argument("--palette", default="ramen")
    ap.add_argument("--sheet", metavar="PNG", help="only draw a preview of every style")
    a = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "..", "..", "palettes", a.palette + ".json")) as f:
        roles = json.load(f)["roles"]
    sts = styles(roles)
    if a.sheet:
        sheet(a.sheet, sts)
        print(f"preview → {a.sheet}")
        return
    picked = sts if a.all else {a.style: sts[a.style]}
    base = os.path.expanduser(a.dest or ("~/.local/share/icons" if a.all else f"~/.local/share/icons/Nook-{a.style}"))
    for name, st in picked.items():
        dest = os.path.join(base, f"Nook-{name}") if a.all else base
        write_theme(dest, f"Nook-{name}", st)
        print(f"Nook-{name} → {dest} ({len(SHAPES)} shapes, sizes {', '.join(map(str, SIZES))})")


if __name__ == "__main__":
    main()
