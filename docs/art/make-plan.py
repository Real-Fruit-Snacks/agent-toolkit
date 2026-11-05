"""Draw the README's load plan: docs/assets/plan-dark.svg and plan-light.svg.

The same plan as the project page, from the same docs/release.json: one column per release asset,
to scale, under a dashed line at 2 GiB, the largest file GitHub accepts. A 14 s loop packs the
columns, grows the split file through the line as one column, cuts it into its parts, seals every
top, and holds. The SVG's base styles are the finished frame, which is what a viewer that skips
the animation shows (and what docs/card.html puts on the social card).

Text is converted to paths from the page's own fonts (docs/fonts), because an SVG shown through
<img> can't load fonts. Deterministic: the same release.json and fonts give the same bytes, and CI
checks that. Run from the repo root:

    python -m pip install -r docs/art/requirements.txt
    python docs/art/make-plan.py
"""
import importlib.util
import json
import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
ROOT = os.path.dirname(DOCS)

# the grouping, sizes and destinations live in scripts/write-page.py, so page and README agree
spec = importlib.util.spec_from_file_location("write_page", os.path.join(ROOT, "scripts", "write-page.py"))
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)

# RFS Nightshift and Dayshift
THEMES = {
    "dark": dict(bg="#0C0D10", line="#262A33", strong="#636872", ink="#E8E6E1", mute="#8A8F99",
                 col="#8A8F99", col_a=0.62, ember="#FF6A3D", mint="#3DDC97", rasp="#F06292"),
    "light": dict(bg="#F6F5F2", line="#D6D3CB", strong="#89867F", ink="#1A1B1E", mute="#666A73",
                  col="#89867F", col_a=0.75, ember="#C03B0A", mint="#15794D", rasp="#B0306A"),
}

W = 1000
X0, X1 = 40, 960            # the plan's left and right edges
CAP = 190                   # height of 2 GiB
S_LABEL, S_NOTE, S_READ, S_HDR, S_TAG = 22, 22, 22, 21, 34   # text sizes, big enough to survive a phone
CG, GG = 4, 18              # gap between columns, extra gap between groups
CYCLE = 14.0
T_RISE, T_PART, T_BREACH, T_SLIDE, T_SEAL, T_DONE, T_RESET = 0.0, 0.9, 1.4, 2.3, 3.0, 4.3, 12.9

MONO, DISPLAY, TEXT = "red-hat-mono-latin.woff2", "red-hat-display-latin.woff2", "red-hat-text-latin.woff2"
_fonts, _glyphs = {}, {}


def glyphset(fname, wght):
    key = (fname, wght)
    if key not in _fonts:
        f = TTFont(os.path.join(DOCS, "fonts", fname))
        _fonts[key] = (f, f.getGlyphSet(location={"wght": wght}), f.getBestCmap(), f["head"].unitsPerEm)
    return _fonts[key]


def advance(s, size, fname, wght):
    _, gs, cmap, upm = glyphset(fname, wght)
    return sum(gs[cmap[ord(ch)]].width for ch in s) * size / upm


def text(s, x, y, size, fname, wght, fill, anchor="start", extra=""):
    """Paths for `s` with its baseline at y; each glyph is drawn once in <defs> and reused."""
    _, gs, cmap, upm = glyphset(fname, wght)
    k = size / upm
    for ch in s:
        if ord(ch) not in cmap:
            sys.exit(f"{fname} has no glyph for {ch!r}")
    width = advance(s, size, fname, wght)
    pen_x = {"start": x, "middle": x - width / 2, "end": x - width}[anchor]
    uses = []
    for ch in s:
        n = cmap[ord(ch)]
        key = (fname, wght, n)
        if key not in _glyphs:
            pen = SVGPathPen(gs, ntos=lambda v: "%g" % round(v, 1))
            gs[n].draw(pen)
            _glyphs[key] = (f"g{len(_glyphs)}", pen.getCommands())
        gid, d = _glyphs[key]
        if d:
            uses.append(f'<use href="#{gid}" transform="matrix({k:.5f} 0 0 {-k:.5f} {pen_x:.2f} {y:.2f})"/>')
        pen_x += gs[n].width * k
    return f'<g fill="{fill}"{extra}>{"".join(uses)}</g>'


def fit(s, size, fname, wght, room):
    """The largest size up to `size` at which `s` fits in `room` px."""
    return min(size, size * room / advance(s, size, fname, wght))


def pct(t):
    return f"{t / CYCLE * 100:.3f}%"


def f2(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def build(theme, data):
    c = THEMES[theme]
    groups, splits = wp.plan(data)
    big = max(splits, key=lambda w: sum(p["size"] for p in splits[w])) if splits else None
    head = max([1.0] + [sum(p["size"] for p in ps) / wp.LIMIT for ps in splits.values()])
    n_cols = sum(len(items) for _, items in groups)
    n_groups = len(groups)
    cw = (X1 - X0 - (n_groups - 1) * GG - (n_cols + n_groups - 2) * CG) / n_cols

    top = 96                              # top of the headroom
    ceil = top + (head - 1) * CAP         # the 2 GiB line
    ground = ceil + CAP
    H = int(ground + 122)

    css, base, body = [], [], []
    # --- the columns ---
    x = X0
    i = 0
    first_part_x = None
    for gi, (g, items) in enumerate(groups):
        if gi:
            x += GG + CG
        gx0 = x
        for a in items:
            h = max(2.0, a["size"] / wp.LIMIT * CAP)
            part = wp.part_no(a["name"]) and wp.whole_of(a["name"]) in splits
            fill = c["ember"] if part else c["col"]
            alpha = "" if part else f' fill-opacity="{c["col_a"]}"'
            cap = min(3.0, h)
            body.append(f'<g class="c{i}"><rect x="{f2(x)}" y="{f2(ground - h)}" width="{f2(cw)}" height="{f2(h)}" fill="{fill}"{alpha}/>'
                        f'<rect class="s{i}" x="{f2(x)}" y="{f2(ground - h)}" width="{f2(cw)}" height="{f2(cap)}" fill="{c["mint"]}"/></g>')
            # grow, and for a part: grow stacked on the parts before it, then slide into its own slot
            t0 = T_RISE + i * 0.018
            t1 = t0 + 0.45
            ease = "animation-timing-function:cubic-bezier(.2,.7,.2,1)"
            if part:
                ps = splits[wp.whole_of(a["name"])]
                k = wp.part_no(a["name"]) - 1
                if wp.whole_of(a["name"]) == big and k == 0:
                    first_part_x = x
                dx = -k * (cw + CG)
                dy = -sum(p["size"] for p in ps[:k]) / wp.LIMIT * CAP
                t0 = T_PART + (-dy / CAP) * 0.5
                t1 = t0 + (h / CAP) * 0.5
                at = f"translate({f2(dx)}px,{f2(dy)}px)"
                kf = [(0, f"{at} scaleY(0)", ""), (t0, f"{at} scaleY(0)", "animation-timing-function:linear"), (t1, f"{at} scaleY(1)", ""),
                      (T_SLIDE, f"{at} scaleY(1)", ease), (T_SLIDE + 0.5, "translate(0px,0px) scaleY(1)", ""),
                      (T_RESET, "translate(0px,0px) scaleY(1)", ""), (T_RESET + 0.4, "translate(0px,0px) scaleY(0)", ""), (CYCLE, f"{at} scaleY(0)", "")]
            else:
                kf = [(0, "scaleY(0)", ""), (t0, "scaleY(0)", ease), (t1, "scaleY(1)", ""), (T_RESET, "scaleY(1)", ""),
                      (T_RESET + 0.4, "scaleY(0)", ""), (CYCLE, "scaleY(0)", "")]
            css.append(f"@keyframes c{i}{{" + "".join(f"{pct(t)}{{transform:{v};{e}}}" for t, v, e in kf) + "}")
            ts = T_SEAL + i * 0.025
            css.append(f"@keyframes s{i}{{0%,{pct(ts)}{{opacity:0}}{pct(ts + 0.12)},{pct(T_RESET)}{{opacity:1}}{pct(T_RESET + 0.2)},100%{{opacity:0}}}}")
            x += cw + CG
            i += 1
        x -= CG
        label = next(lb for k, lb, _ in wp.GROUPS if k == g)
        body.append(f'<rect x="{f2(gx0)}" y="{f2(ground)}" width="{f2(x - gx0)}" height="1" fill="{c["strong"]}"/>')
        if g != "repo":
            t = text(label, gx0, ground + 31, S_LABEL, MONO, 500, c["ink"])
            t += text(f" {len(items)}", gx0 + advance(label, S_LABEL, MONO, 500), ground + 31, S_LABEL, MONO, 400, c["mute"])
            body.append(t)
        x += CG
    anim = "".join(f".c{k}{{animation:c{k} {CYCLE}s infinite}}.s{k}{{animation:s{k} {CYCLE}s infinite}}" for k in range(i))
    for k in range(i):
        base.append(f".c{k}{{transform-box:fill-box;transform-origin:50% 100%}}")

    # --- the 2 GiB line and its label ---
    lines = [f'<line class="lim" x1="{X0}" y1="{f2(ceil)}" x2="{X1}" y2="{f2(ceil)}" stroke="{c["strong"]}" stroke-width="2" stroke-dasharray="9 6"/>',
             text("2 GiB", X0, ceil + 31, S_LABEL, MONO, 500, c["ink"]),
             text(" the largest file GitHub takes", X0 + advance("2 GiB", S_LABEL, MONO, 500), ceil + 31, S_LABEL, MONO, 400, c["mute"], extra=' class="std"')]
    css.append(f"@keyframes lim{{0%,{pct(T_BREACH)}{{stroke:{c['strong']}}}{pct(T_BREACH + 0.001)},{pct(T_SLIDE + 0.05)}{{stroke:{c['rasp']}}}{pct(T_SLIDE + 0.051)},100%{{stroke:{c['strong']}}}}}")
    anim += f".lim{{animation:lim {CYCLE}s step-end infinite}}"

    # --- the split file: its outline before the cut, and the note ---
    if big:
        ps = splits[big]
        whole = sum(p["size"] for p in ps)
        h1 = ps[0]["size"] / wp.LIMIT * CAP
        hw = whole / wp.LIMIT * CAP
        gx = first_part_x
        ghost = [f'<rect x="{f2(gx + 0.5)}" y="{f2(ground - hw + 0.5)}" width="{f2(cw - 1)}" height="{f2(hw - h1 - 0.5)}" fill="none" stroke="{c["strong"]}" stroke-dasharray="4 3"/>']
        for k in range(2, len(ps)):
            yk = ground - sum(p["size"] for p in ps[:k]) / wp.LIMIT * CAP
            ghost.append(f'<rect x="{f2(gx - 5)}" y="{f2(yk - 1)}" width="{f2(cw + 10)}" height="2" fill="{c["ember"]}"/>')
        lines.append(f'<g class="ghost">{"".join(ghost)}</g>')
        css.append(f"@keyframes ghost{{0%,{pct(T_SLIDE + 0.2)}{{opacity:0}}{pct(T_SLIDE + 0.6)},{pct(T_RESET)}{{opacity:1}}{pct(T_RESET + 0.2)},100%{{opacity:0}}}}")
        anim += f".ghost{{animation:ghost {CYCLE}s infinite}}"
        nx = gx - 18
        name = wp.short(big)
        l1 = f" is {wp.size(whole)}, so it ships"
        w1 = advance(name, S_NOTE, MONO, 500) + advance(l1, S_NOTE, TEXT, 400)
        lines.append(text(name, nx - w1, ceil - 46, S_NOTE, MONO, 500, c["ink"]) + text(l1, nx - w1 + advance(name, S_NOTE, MONO, 500), ceil - 46, S_NOTE, TEXT, 400, c["mute"]))
        lines.append(text(f"as {len(ps)} parts of 1900 MiB or less", nx, ceil - 17, S_NOTE, TEXT, 400, c["mute"], anchor="end"))
        # while the file is too big, the line's label says so instead
        over = text(f" {name} is over it", X0 + advance("2 GiB", S_LABEL, MONO, 500), ceil + 31, S_LABEL, MONO, 500, c["rasp"], extra=' class="over"')
        lines.append(over)
        css.append(f"@keyframes over{{0%,{pct(T_BREACH)}{{opacity:0}}{pct(T_BREACH + 0.001)},{pct(T_SLIDE + 0.05)}{{opacity:1}}{pct(T_SLIDE + 0.051)},100%{{opacity:0}}}}")
        css.append(f"@keyframes std{{0%,{pct(T_BREACH)}{{opacity:1}}{pct(T_BREACH + 0.001)},{pct(T_SLIDE + 0.05)}{{opacity:0}}{pct(T_SLIDE + 0.051)},100%{{opacity:1}}}}")
        anim += f".over{{animation:over {CYCLE}s step-end infinite}}.std{{animation:std {CYCLE}s step-end infinite}}"
        base.append(".over{opacity:0}")

    # --- the header and the readout ---
    n = len(data["assets"])
    total = wp.size(sum(a["size"] for a in data["assets"]))
    day = wp.published(data)[0].split(",")[0]
    hdr = [text(data["tag"], X0, 54, S_TAG, DISPLAY, 800, c["ink"]),
           text(f"{n} assets · {total} · {day}", X0 + advance(data["tag"], S_TAG, DISPLAY, 800) + 18, 54, S_HDR, MONO, 400, c["mute"]),
           text("one column per asset, to scale", X1, 54, S_HDR, TEXT, 400, c["mute"], anchor="end")]
    ry = H - 28
    room = X1 - X0

    def line(s, fill):
        return text(s, X0, ry, fit(s, S_READ, MONO, 500, room), MONO, 500, fill)

    say = [("pack", T_RISE, T_BREACH if big else T_SEAL, line(f"Packing {data['tag']}: {n} assets, {total}", c["ink"]))]
    if big:
        whole = sum(p["size"] for p in splits[big])
        say.append(("sover", T_BREACH, T_SLIDE, line(f"{wp.short(big)} is {wp.size(whole)}: over GitHub's 2 GiB limit", c["rasp"])))
        say.append(("ssplit", T_SLIDE, T_SEAL, line(f"package-release.ps1 cuts it into {len(splits[big])} parts and a .sha256", c["ink"])))
    say.append(("sver", T_SEAL, T_DONE, line(f"verify-release.ps1: checking {n} digests against SHA256SUMS.txt", c["ink"])))
    a, b = f"Release {data['tag']} is ", "consistent"
    rest = f": {n} assets, digests match SHA256SUMS.txt."
    sz = fit(a + b + rest, S_READ, MONO, 500, room)
    done = (text(a, X0, ry, sz, MONO, 500, c["ink"]) + text(b, X0 + advance(a, sz, MONO, 500), ry, sz, MONO, 500, c["mint"])
            + text(rest, X0 + advance(a + b, sz, MONO, 500), ry, sz, MONO, 500, c["ink"]))
    say.append(("sdone", T_DONE, T_RESET + 0.4, done))
    for cls, t0, t1, t in say:
        shown_at_rest = cls == "sdone"
        base.append(f".{cls}{{opacity:{1 if shown_at_rest else 0}}}")
        css.append(f"@keyframes {cls}{{0%{{opacity:{1 if t0 == 0 else 0}}}{pct(t0)}{{opacity:1}}{pct(t1)}{{opacity:0}}100%{{opacity:{1 if t0 == 0 else 0}}}}}")
        anim += f".{cls}{{animation:{cls} {CYCLE}s step-end infinite}}"
    readout = [f'<g class="{cls}">{t}</g>' for cls, _, _, t in say]

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img">']
    o.append(f"<style>{''.join(base)}@media (prefers-reduced-motion:no-preference){{{''.join(css)}{anim}}}</style>")
    o.append(f'<rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="16" fill="{c["bg"]}" stroke="{c["line"]}"/>')
    o += hdr
    o.append(f'<rect x="{X0}" y="{H - 68}" width="{X1 - X0}" height="1" fill="{c["line"]}"/>')
    o += lines
    o += body
    o += readout
    defs = "".join(f'<path id="{gid}" d="{d}"/>' for gid, d in _glyphs.values() if d)
    o.insert(1, f"<defs>{defs}</defs>")
    o.append("</svg>")
    return "".join(o)


def main():
    with open(os.path.join(DOCS, "release.json"), encoding="utf-8") as fh:
        data = json.load(fh)
    for theme in THEMES:
        _glyphs.clear()
        path = os.path.join(DOCS, "assets", f"plan-{theme}.svg")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(build(theme, data) + "\n")
        print(f"wrote {os.path.relpath(path, ROOT)} ({os.path.getsize(path) // 1024} KB)")


if __name__ == "__main__":
    main()
