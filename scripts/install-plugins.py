#!/usr/bin/env python3
"""Install the vendored Claude Code plugin marketplaces, offline.

  * copies caches/claude-plugins/<marketplace>/ to --marketplaces (default
    ~/.claude-toolkit/marketplaces; plugins load in place from there, so it must be
    a stable location)
  * registers each marketplace with `claude plugin marketplace add <dir>`
  * installs the plugins listed as enabled with `claude plugin install`
  * installs the language servers the LSP plugins call: npm ones from the
    seeded npm cache, binaries from caches/lsp-bin into --bin (default ~/.local/bin)
  * checks `claude plugin list --json` and fails if an enabled plugin has errors

Works on Windows, WSL and Linux. Re-running is safe: existing marketplaces are
refreshed in place and already-installed plugins are left alone. install-windows.ps1
passes the install root's plugins and bin folders.

Usage: python install-plugins.py [--repo DIR] [--claude PATH] [--marketplaces DIR] [--bin DIR]
                                 [--skip-lsp] [--skip-lsp-npm] [--all]
"""
import argparse, glob, gzip, json, os, shutil, subprocess, sys, zipfile

ap = argparse.ArgumentParser()
ap.add_argument('--repo', default=os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
ap.add_argument('--claude', default=None, help='path to the claude binary')
ap.add_argument('--skip-lsp', action='store_true', help='skip all language servers')
ap.add_argument('--skip-lsp-npm', action='store_true', help='skip the npm language servers (installed separately, e.g. as root on Linux)')
ap.add_argument('--all', action='store_true', help='install every vendored plugin, not just the defaults')
ap.add_argument('--marketplaces', default=None, help='where the marketplaces are copied to and load from')
ap.add_argument('--bin', default=None, help='where the language-server binaries go')
args = ap.parse_args()

WIN = os.name == 'nt'
HOME = os.path.expanduser('~')
SRC = os.path.join(args.repo, 'caches', 'claude-plugins')
DEST = args.marketplaces or os.path.join(HOME, '.claude-toolkit', 'marketplaces')
LOCAL_BIN = args.bin or os.path.join(HOME, '.local', 'bin')


def find_claude():
    if args.claude:
        return args.claude
    for c in [shutil.which('claude'), os.path.join(LOCAL_BIN, 'claude.exe' if WIN else 'claude')]:
        if c and os.path.exists(c):
            return c
    sys.exit('claude binary not found; install Claude Code first or pass --claude')


def run_json(cmd):
    """Run a claude CLI command with --json and return the parsed last JSON line."""
    p = subprocess.run(cmd + ['--json'], capture_output=True, text=True, encoding='utf-8', errors='replace')
    for line in reversed((p.stdout or '').splitlines()):
        line = line.strip()
        if line.startswith('{') or line.startswith('['):
            try:
                return json.loads(line)
            except ValueError:
                pass
    return {'outcome': 'failed', 'message': (p.stderr or p.stdout or '').strip()[:400], 'exit': p.returncode}


def copytree(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def install_marketplaces(claude):
    index = json.load(open(os.path.join(SRC, 'index.json'), encoding='utf-8'))['marketplaces']
    os.makedirs(DEST, exist_ok=True)
    want, failed = [], []
    for m in index:
        target = os.path.join(DEST, m['dir'])
        copytree(os.path.join(SRC, m['dir']), target)
        r = run_json([claude, 'plugin', 'marketplace', 'add', target])
        ok = r.get('outcome') == 'ok' or 'already' in r.get('message', '')
        print(f"  marketplace {m['name']:28s} {'ok' if ok else 'FAILED: ' + r.get('message', '')}")
        if not ok:
            failed.append(m['name'])
            continue
        for p in (m['plugins'] if args.all else m['enable']):
            want.append(f"{p}@{m['name']}")
    for pid in want:
        r = run_json([claude, 'plugin', 'install', pid])
        ok = r.get('outcome') == 'ok' or 'already installed' in r.get('message', '')
        print(f"  plugin      {pid:45s} {'ok' if ok else 'FAILED: ' + r.get('message', '')}")
        if not ok:
            failed.append(pid)
    return want, failed


def install_lsp():
    cfg = json.load(open(os.path.join(args.repo, 'config', 'plugin-sources.json'), encoding='utf-8')).get('lsp', {})
    # On Windows, the kit's own per-user Node first (install-windows.ps1 puts it there), then PATH,
    # then an all-users install, the same order as Find-Npm in common.ps1.
    root = os.environ.get('AGENT_TOOLKIT_HOME') or os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Programs', 'agent-toolkit')
    own = os.path.join(root, 'node', 'npm.cmd') if WIN else ''
    npm = (own if own and os.path.exists(own) else None) or shutil.which('npm.cmd' if WIN else 'npm') or shutil.which('npm')
    if not npm and WIN:
        c = os.path.join(os.environ.get('ProgramFiles', r'C:\Program Files'), 'nodejs', 'npm.cmd')
        npm = c if os.path.exists(c) else None
    cache = os.environ.get('npm_config_cache') or os.path.join(HOME, '.npm-toolkit-cache')
    if args.skip_lsp_npm:
        print('  lsp npm     skipped (--skip-lsp-npm)')
    elif npm and cfg.get('npm') and os.path.isdir(cache):
        for pkg in cfg['npm']:  # one at a time, matching how the cache was seeded
            p = subprocess.run([npm, 'install', '-g', '--offline', '--cache', cache, '--no-audit', '--no-fund', pkg], capture_output=True, text=True)
            print(f"  lsp npm     {pkg}: {'ok' if p.returncode == 0 else 'FAILED: ' + (p.stderr or '')[-300:]}")
    else:
        print('  lsp npm     skipped (npm or the seeded npm cache is missing)')
    os.makedirs(LOCAL_BIN, exist_ok=True)
    side = 'win' if WIN else 'linux'
    for b in cfg.get('bin', []):
        asset = b['asset_win'] if WIN else b['asset_linux']
        src = os.path.join(args.repo, 'caches', 'lsp-bin', side, asset)
        exe = os.path.join(LOCAL_BIN, b['bin'] + ('.exe' if WIN else ''))
        if not os.path.exists(src):
            print(f"  lsp bin     {b['id']}: missing {asset}")
            continue
        if asset.endswith('.zip'):
            with zipfile.ZipFile(src) as z:
                member = next(n for n in z.namelist() if os.path.basename(n).lower() == os.path.basename(exe).lower())
                with z.open(member) as fi, open(exe, 'wb') as fo:
                    shutil.copyfileobj(fi, fo)
        elif asset.endswith('.gz'):
            with gzip.open(src) as fi, open(exe, 'wb') as fo:
                shutil.copyfileobj(fi, fo)
        if not WIN:
            os.chmod(exe, 0o755)
        print(f"  lsp bin     {b['id']}: {exe}")


def verify(claude, want):
    p = subprocess.run([claude, 'plugin', 'list', '--json'], capture_output=True, text=True, encoding='utf-8', errors='replace')
    try:
        listed = {x['id']: x for x in json.loads(p.stdout)}
    except ValueError:
        print('  could not parse `claude plugin list --json`:', (p.stdout or p.stderr)[:300])
        return False
    bad = []
    for pid in want:
        x = listed.get(pid)
        if not x:
            bad.append(f'{pid}: not listed')
        elif not x.get('enabled'):
            bad.append(f'{pid}: installed but disabled')
        elif x.get('errors'):
            bad.append(f"{pid}: {x['errors']}")
    print(f'  verified    {len(want) - len(bad)}/{len(want)} plugins enabled and loading')
    for b in bad:
        print('    ' + b)
    return not bad


def main():
    claude = find_claude()
    os.environ.setdefault('DISABLE_AUTOUPDATER', '1')
    os.environ.setdefault('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', '1')
    print('== Claude Code plugins')
    want, failed = install_marketplaces(claude)
    if not args.skip_lsp:
        print('== Language servers for the LSP plugins')
        install_lsp()
    ok = verify(claude, [w for w in want if w not in failed])
    sys.exit(0 if ok and not failed else 1)


if __name__ == '__main__':
    main()
