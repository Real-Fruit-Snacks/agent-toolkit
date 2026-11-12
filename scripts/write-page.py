"""Writes the release facts on the project page: docs/release.json, the generated blocks in docs/index.html,
and the smoke test's log in README.md.

    python scripts/write-page.py --tag v1.0.4 --log install.log --check check.log
                                  # read a published release, VERSIONS.md and the build's logs, then write all three
    python scripts/write-page.py  # rewrite the page and the README from the committed docs/release.json

The weekly-release workflow runs the first form after it publishes, with the logs of the install it ran as
a standard user, then docs/art/make-plan.py draws the README's load plan from the same docs/release.json.
Without --log, the log already in docs/release.json is kept. CI runs the second form and fails if the page
or the README changes, so a hand edit inside a generated block shows up. Each block sits between
<!-- gen:NAME --> and <!-- /gen:NAME -->; everything outside them is hand-written.

Python 3.9+, standard library only. The --tag form needs the GitHub CLI.
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "docs", "index.html")
README = os.path.join(ROOT, "README.md")
DATA = os.path.join(ROOT, "docs", "release.json")
REPO = "Real-Fruit-Snacks/agent-toolkit"

GIB, MIB, KIB = 1 << 30, 1 << 20, 1 << 10
LIMIT = 2 * GIB             # GitHub takes release assets under 2 GiB
PART = 1900 * MIB           # package-release.ps1 cuts anything this size or bigger into parts

# The load plan's groups, left to right: what unpack-release.ps1 does with each asset prefix.
GROUPS = [
    ("repo", "repo", "the repo itself and SHA256SUMS.txt"),
    ("windows", "windows\\", "installers for Windows"),
    ("linux", "linux\\", "installers for Linux"),
    ("caches", "caches\\", "zipped caches, skills, plugins and docs"),
    ("wsl", "wsl\\", "the WSL platform and the Ubuntu distro"),
]

# VERSIONS.md rows shown in the pin table: (label on the page, row label written by write-versions.ps1)
PINS = [
    ("T3 Code", "T3 Code (Windows installer)"),
    ("Claude Code CLI", "Claude Code (Windows)"),
    ("Node.js", "Node.js (Windows zip)"),
    ("Git for Windows", "Git for Windows (portable)"),
    ("GitHub CLI", "GitHub CLI (Windows zip)"),
    ("PowerShell 7", "PowerShell 7 (Windows zip)"),
    ("Python", "Python (Windows NuGet)"),
    ("WSL platform", "WSL platform"),
    ("Ubuntu for WSL", "Ubuntu WSL rootfs"),
]


# ---------- reading the release ----------

def section(md, title):
    """Lines under a '## title' heading of VERSIONS.md, up to the next heading."""
    m = re.search(r"^## " + re.escape(title) + r"[^\n]*\n(.*?)(?=^## |\Z)", md, re.M | re.S)
    return [ln.strip() for ln in m.group(1).splitlines() if ln.strip()] if m else []


def read_versions():
    with open(os.path.join(ROOT, "VERSIONS.md"), encoding="utf-8") as fh:
        md = fh.read()
    rows = {}
    for ln in md.splitlines():
        m = re.match(r"^\| ([^|]+?) \| ([^|]+?) \| `([^`]+)` \|", ln)
        if m:
            rows[m.group(1)] = m.group(2)
    pins = [[label, rows[key]] for label, key in PINS if key in rows]
    items = lambda title: [ln[2:] for ln in section(md, title) if ln.startswith("- ")]
    t3 = items("T3 tool cache")
    browsers = [b for b in items("Playwright browsers") if b.startswith("chromium")]
    tgz = [re.sub(r"\.tgz$", "", t) for t in items("npm tarballs")]
    pw = next((t[len("playwright-"):] for t in tgz if re.match(r"playwright-\d", t)), None)
    if t3:
        pins.append(["T3 tool cache", ", ".join(t3)])
    if pw:
        pins.append(["Playwright", pw + (" with " + " and ".join(browsers) if browsers else "")])

    skills = next((ln.split(":", 1)[1].strip() for ln in items("Also in the release") if ln.startswith("caches/claude-skills:")), "")

    markets = []
    for ln in section(md, "Claude Code plugin marketplaces"):
        m = re.match(r"^\| `([^`]+)` \| ([^|]+?) \| `([0-9a-f]+)` \| (\d+) \| ([^|]+?) \|$", ln)
        if m:
            on = [] if m.group(5).strip() == "-" else [p.strip() for p in m.group(5).split(",")]
            markets.append({"name": m.group(1), "upstream": m.group(2), "commit": m.group(3), "plugins": int(m.group(4)), "enabled": on})

    mcp = {}
    for ln in section(md, "MCP servers"):
        m = re.match(r"^- (npm|pip|bin): (.+)$", ln)
        if m:
            mcp[m.group(1)] = [[s.strip("* "), s.strip().startswith("**")] for s in m.group(2).split(",")]
    return {"pins": pins, "skills": skills, "marketplaces": markets, "mcp": mcp}


def read_release(tag):
    out = subprocess.run(["gh", "release", "view", tag, "--repo", REPO, "--json", "tagName,publishedAt,assets"],
                         capture_output=True, text=True, check=True).stdout
    rel = json.loads(out)
    assets = []
    for a in rel["assets"]:
        if a["name"].startswith("page--"):
            continue   # this page itself, uploaded after the rest: not part of the load it describes
        d = (a.get("digest") or "").removeprefix("sha256:")
        if not re.fullmatch(r"[0-9a-f]{64}", d):
            sys.exit(f"{a['name']} has no sha256 digest on the release")
        assets.append({"name": a["name"], "size": a["size"], "sha256": d})
    assets.sort(key=lambda a: a["name"].lower())
    return {"tag": rel["tagName"], "published": rel["publishedAt"], "assets": assets}


# ---------- shared with docs/art/make-plan.py ----------

def group_of(name):
    p = name.split("--", 1)[0] if "--" in name else ""
    return p if p in ("windows", "linux", "caches", "wsl") else "repo"


def whole_of(name):
    """The file a part or sidecar belongs to: wsl--ubuntu-dev.tar.gz.part2 -> wsl--ubuntu-dev.tar.gz."""
    return re.sub(r"\.(part\d+|sha256)$", "", name)


def part_no(name):
    m = re.search(r"\.part(\d+)$", name)
    return int(m.group(1)) if m else 0


def plan(data):
    """Assets in load-plan order, grouped, biggest file first, a split file's parts side by side.
    Returns [(group key, [asset, ...]), ...] and the split files {whole name: [part, ...]}."""
    assets = data["assets"]
    totals = {}
    for a in assets:
        totals[whole_of(a["name"])] = totals.get(whole_of(a["name"]), 0) + a["size"]
    key = lambda a: (-totals[whole_of(a["name"])], whole_of(a["name"]), a["name"].endswith(".sha256"), part_no(a["name"]))
    groups = [(g, sorted((a for a in assets if group_of(a["name"]) == g), key=key)) for g, _, _ in GROUPS]
    groups = [(g, items) for g, items in groups if items]
    splits = {}
    for a in assets:
        if part_no(a["name"]):
            splits.setdefault(whole_of(a["name"]), []).append(a)
    for w in splits:
        splits[w].sort(key=lambda a: part_no(a["name"]))
    return groups, splits


def size(n):
    if n >= GIB:
        return f"{n / GIB:.2f} GiB"
    if n >= MIB:
        v = n / MIB
        return f"{v:.0f} MiB" if v >= 10 else f"{v:.1f} MiB"
    if n >= KIB:
        v = n / KIB
        return f"{v:.0f} KiB" if v >= 10 else f"{v:.1f} KiB"
    return f"{n} bytes"


def short(name):
    """The file name without its folder prefix."""
    return name.split("--", 1)[1] if "--" in name else name


def destination(name):
    """Where unpack-release.ps1 puts an asset (see that script)."""
    if part_no(name):
        return f"joined into wsl\\{short(whole_of(name))}"
    if name.endswith(".sha256"):
        return f"checks the joined {short(whole_of(name))}"
    if name.startswith("repo--"):
        return "the repo itself, for a machine without a clone"
    if name == "SHA256SUMS.txt":
        return "the SHA-256 of every other asset"
    g = group_of(name)
    if g == "caches":
        return f"unzips to caches\\{re.sub(r'[.]zip$', '', short(name))}\\"
    if short(name).startswith("claude-"):
        return f"goes to {g}\\claude-code\\"
    return f"goes to {g}\\"


def published(data):
    t = datetime.strptime(data["published"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return t.strftime("%d %b %Y, %H:%M UTC").lstrip("0"), t.strftime("%Y-%m-%dT%H:%MZ")


# ---------- the page blocks ----------

def e(s):
    return html.escape(str(s), quote=True)


def num(x):
    return f"{x:.4f}".rstrip("0").rstrip(".") or "0"


def block_plan(data):
    groups, splits = plan(data)
    tag, n = data["tag"], len(data["assets"])
    total = sum(a["size"] for a in data["assets"])
    tracks, cols, labels = [], [], []
    col = 0
    big = max(splits, key=lambda w: sum(p["size"] for p in splits[w])) if splits else None
    head = max([1.0] + [sum(p["size"] for p in ps) / LIMIT for ps in splits.values()])
    first_part = None
    for gi, (g, items) in enumerate(groups):
        if gi:
            tracks.append("var(--gg)")
            col += 1
        start = col + 1
        for a in items:
            col += 1
            tracks.append("1fr")
            h = a["size"] / LIMIT
            style = f"--h:{num(h)};--i:{len(cols)};grid-column:{col}"
            cls = "col"
            if part_no(a["name"]) and whole_of(a["name"]) in splits:
                ps = splits[whole_of(a["name"])]
                k = part_no(a["name"]) - 1
                below = sum(p["size"] for p in ps[:k]) / LIMIT
                style += f";--dx:{k};--dy:{num(below)};--hw:{num(sum(p['size'] for p in ps) / LIMIT)}"
                cls += " part"
                if whole_of(a["name"]) == big and k == 0:
                    first_part = col
            cols.append(f'<li class="{cls}" style="{style}" data-n="{e(a["name"])}" data-s="{size(a["size"])}" '
                        f'data-d="{a["sha256"][:12]}" data-to="{e(destination(a["name"]))}"></li>')
        label = next(lb for k, lb, _ in GROUPS if k == g)
        labels.append(f'<li style="grid-column:{start} / {col + 1}"><b>{e(label)}</b> <span>{len(items)}</span></li>')

    o = [f'<div class="stage" style="--head:{num(head)};grid-template-columns:{" ".join(tracks)}">']
    over = f'<span class="over" aria-hidden="true">{e(short(big))} is over it</span>' if big else ""
    o.append(f'<p class="limit"><span>2&nbsp;GiB</span> <span class="std">the largest file GitHub takes</span>{over}</p>')
    if big:
        ps = splits[big]
        whole = sum(p["size"] for p in ps)
        o.append(f'<p class="note" style="grid-column:1 / {first_part}"><b>{e(short(big))}</b> is {size(whole)}, '
                 f'so it ships as {len(ps)}&nbsp;parts of 1900&nbsp;MiB or less</p>')
        # where the file stood before it was cut: the outline above its first part, with the cuts marked
        h1 = ps[0]["size"] / LIMIT
        cuts = "".join(f'<i style="--at:{num(sum(p["size"] for p in ps[:k]) / LIMIT - h1)}"></i>' for k in range(2, len(ps)))
        o.append(f'<span class="ghost" style="grid-column:{first_part};--h1:{num(h1)};--hw:{num(whole / LIMIT)}" aria-hidden="true">{cuts}</span>')
    o.append('<ol class="cols" aria-hidden="true">' + "".join(cols) + "</ol>")
    o.append('<ol class="groups" aria-hidden="true">' + "".join(labels) + "</ol>")
    o.append("</div>")

    lines = {
        "pack": f"Packing {tag}: {n} assets, {size(total)}",
        "done": f"Release {tag} is consistent: {n} assets, digests match SHA256SUMS.txt.",
    }
    if big:
        lines["over"] = f"{short(big)} is {size(sum(p['size'] for p in splits[big]))}: over GitHub's 2 GiB limit"
        lines["split"] = f"package-release.ps1 cuts it into {len(splits[big])} parts, plus a .sha256 to check the join"
    attrs = " ".join(f'data-{k}="{e(v)}"' for k, v in lines.items())
    o.append(f'<div class="plan-foot" {attrs} data-count="{n}">')
    o.append(f'<p class="readout" id="readout" aria-live="polite">{e(lines["done"])}</p>')
    o.append("</div>")
    return "".join(o)


def block_label(data):
    n = len(data["assets"])
    total = sum(a["size"] for a in data["assets"])
    when, iso = published(data)
    num_, unit = size(total).split(" ")
    return (f'<div><dt>release</dt><dd>{e(data["tag"])}</dd></div>'
            f'<div><dt>published</dt><dd><time datetime="{iso}">{e(when)}</time></dd></div>'
            f'<div class="big"><dt>assets</dt><dd>{n}</dd></div>'
            f'<div class="big"><dt>in total</dt><dd>{num_}<small>&nbsp;{unit}</small></dd></div>')


def block_pins(data):
    rows = "".join(f"<tr><th scope=\"row\">{e(k)}</th><td><code>{e(v)}</code></td></tr>" for k, v in data["pins"])
    return f"<tbody>{rows}</tbody>"


def block_counts(data):
    mk = data["marketplaces"]
    plugins = sum(m["plugins"] for m in mk)
    enabled = sum(len(m["enabled"]) for m in mk)
    servers = [s for kind in data["mcp"].values() for s in kind]
    on = sum(1 for _, d in servers if d)
    return (f'<li><b class="qty">{len(servers)}</b><span><strong>MCP servers</strong>, {on} registered by default, '
            f'the rest one <code>claude mcp add</code> away</span></li>'
            f'<li><b class="qty">{plugins}</b><span><strong>plugins</strong> from {len(mk)} vendored marketplaces, '
            f'{enabled} enabled</span></li>')


def block_markets(data):
    rows = []
    for m in data["marketplaces"]:
        on = ", ".join(m["enabled"]) if m["enabled"] else "none"
        rows.append(f'<tr><th scope="row"><code>{e(m["name"])}</code></th><td>{e(m["upstream"])}</td>'
                    f'<td class="n">{m["plugins"]}</td><td>{e(on)}</td></tr>')
    return "<tbody>" + "".join(rows) + "</tbody>"


def block_mcp(data):
    names = {"npm": "From npm", "pip": "From PyPI", "bin": "As binaries"}
    o = []
    for k in ("npm", "pip", "bin"):
        if k in data["mcp"]:
            ids = ", ".join(f"<b>{e(i)}</b>" if d else e(i) for i, d in data["mcp"][k])
            o.append(f"<p><span class=\"k\">{names[k]}</span> {ids}</p>")
    return "".join(o)


def block_assets(data):
    groups, _ = plan(data)
    rows = []
    for _, items in groups:
        for a in items:
            rows.append(f'<tr><td><code>{e(a["name"])}</code></td><td class="n">{size(a["size"])}</td>'
                        f'<td><code class="sha">{a["sha256"]}</code></td></tr>')
    return "<tbody>" + "".join(rows) + "</tbody>"


# ---------- the smoke test's logs ----------

# a line that only says something worked: "  ok  playwright", "  marketplace x   ok", "  lsp npm  pyright: ok"
OK_LINE = re.compile(r"^\s+(?:ok\s+\S.*|.*[\s:]ok)$")


def read_log(path, collapse):
    """A log the release build saved, as lines: CRs and trailing spaces gone, and with collapse,
    each run of more than three ok lines cut to its first two and a count."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = [ln.rstrip() for ln in fh.read().lstrip("﻿").replace("\r", "").split("\n")]
    out, run = [], []

    def flush():
        out.extend(run if len(run) <= 3 else run[:2] + [f"  ({len(run) - 2} more, all ok)"])
        run.clear()

    for ln in raw:
        if collapse and OK_LINE.match(ln):
            run.append(ln)
        else:
            flush()
            out.append(ln)
    flush()
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return out


def read_logs(install, check, tag):
    lines = read_log(install, True)
    checks = read_log(check, False) if check else []
    m = next((re.match(r"^== Installing for (?:[^\\\s]+\\)?(\S+), into ", ln) for ln in lines if ln.startswith("== Installing for ")), None)
    standard = any(re.match(r"^\s+ok\s+account\s.*a standard user", ln) for ln in checks)
    return {"tag": tag, "user": m.group(1) if m else "", "standard": standard, "flags": "", "lines": lines, "check": checks}


def log_caption(log, code, b=lambda s: s):
    """The words under the log; code() marks up a file or flag, for HTML or Markdown."""
    if log["standard"]:
        return (f"What {code('install-windows.ps1')} printed in the {log['tag']} build's smoke test, as {code(log['user'])}: "
                f"a new account with {b('no admin rights')} on a clean GitHub Actions Windows runner, in Windows PowerShell 5.1, "
                f"the whole install. Then {code('check-install.ps1')}, as the same account. Runs of ok lines are cut short where it says so.")
    return (f"What {code('install-windows.ps1')} printed in the {log['tag']} build's smoke test. That build ran it as the runner's "
            f"administrator, {code(log['user'])}, with the app installers and the environment skipped ({code(log['flags'])}). "
            f"From the next build on, this is the whole install run as a new account with no admin rights.")


def log_lines(log):
    # check-install.ps1 opens with its own command line, so the second log needs only a gap
    return list(log["lines"]) + ([""] + log["check"] if log["check"] else [])


def block_log(data):
    log = data["install_log"]
    rows = []
    for ln in log_lines(log):
        s = e(ln)
        if ln.startswith("== "):
            s = f'<span class="h">{s}</span>'
        elif ln.startswith("WARNING") or re.match(r"^\s+FAIL\s", ln):
            s = f'<span class="w">{s}</span>'
        elif re.match(r"^\s+\(\d+ more", ln):
            s = f'<span class="cut">{s}</span>'
        else:
            s = re.sub(r"(?<=\s)ok(?=\s|$)", '<span class="ok">ok</span>', s, count=1)
        rows.append(s)
    cap = log_caption(log, lambda c: f"<code>{e(c)}</code>", lambda w: f"<strong>{w}</strong>")
    return f"<figcaption>{cap}</figcaption>\n<pre><code>" + "\n".join(rows) + "</code></pre>"


def readme_log(data):
    log = data["install_log"]
    return "\n" + log_caption(log, lambda c: f"`{c}`", lambda w: f"**{w}**") + "\n\n```text\n" + "\n".join(log_lines(log)) + "\n```\n"


def blocks(data):
    tag = data["tag"]
    n = len(data["assets"])
    servers = sum(len(v) for v in data["mcp"].values())
    plugins = sum(m["plugins"] for m in data["marketplaces"])
    return {
        "plan": block_plan(data),
        "label": block_label(data),
        "get": f'<a class="get" href="https://github.com/{REPO}/releases/tag/{e(tag)}">Get {e(tag)} from GitHub</a>',
        "mcp-count": str(servers),
        "plugin-count": str(plugins),
        "pins": block_pins(data),
        "counts": block_counts(data),
        "skills": e(data["skills"]),
        "markets": block_markets(data),
        "mcp": block_mcp(data),
        "asset-count": str(n),
        "assets": block_assets(data),
        "log": block_log(data),
    }


def fill(text, name, body, where):
    pat = re.compile(r"(<!-- gen:" + re.escape(name) + r" -->)(.*?)(<!-- /gen:" + re.escape(name) + r" -->)", re.S)
    if not pat.search(text):
        sys.exit(f"{where} has no <!-- gen:{name} --> block")
    return pat.sub(lambda m: m.group(1) + body + m.group(3), text)


def render(page, data):
    for name, body in blocks(data).items():
        page = fill(page, name, body, "docs/index.html")
    # the release workflow also rewrites this heading with a regex; keep the two in step
    page, n = re.subn(r"<h2>Pinned in v[0-9.]+</h2>", f"<h2>Pinned in {data['tag']}</h2>", page)
    if n != 1:
        sys.exit("docs/index.html needs exactly one <h2>Pinned in vX</h2>, attribute-free: weekly-release.yml rewrites it")
    # the hero keeps the label clear of the tallest split file, so it needs the plan's headroom too
    _, splits = plan(data)
    head = max([1.0] + [sum(p["size"] for p in ps) / LIMIT for ps in splits.values()])
    page, n = re.subn(r'(<section class="hero" style="--head:)[0-9.]+(")', lambda m: m.group(1) + num(head) + m.group(2), page)
    if n != 1:
        sys.exit('docs/index.html has no <section class="hero" style="--head:N">')
    return page


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tag", help="read this published release with gh and VERSIONS.md, and write docs/release.json")
    ap.add_argument("--log", help="with --tag: what install-windows.ps1 printed in the build's smoke test")
    ap.add_argument("--check", help="with --log: what check-install.ps1 printed after it")
    args = ap.parse_args()
    if args.log and not args.tag:
        ap.error("--log goes with --tag")
    if args.tag:
        with open(DATA, encoding="utf-8") as fh:
            before = json.load(fh)
        data = read_release(args.tag)
        data.update(read_versions())
        # a run without --log keeps the log the page already shows, with the build it came from
        data["install_log"] = read_logs(args.log, args.check, args.tag) if args.log else before["install_log"]
        with open(DATA, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
        print(f"wrote docs/release.json ({data['tag']}, {len(data['assets'])} assets, log from {data['install_log']['tag']})")
    with open(DATA, encoding="utf-8") as fh:
        data = json.load(fh)
    for path, make in ((PAGE, lambda t: render(t, data)), (README, lambda t: fill(t, "log", readme_log(data), "README.md"))):
        with open(path, encoding="utf-8") as fh:
            old = fh.read()
        new = make(old)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(new)
        print(f"wrote {os.path.relpath(path, ROOT)} ({'changed' if new != old else 'no change'})")


if __name__ == "__main__":
    main()
