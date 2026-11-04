#!/usr/bin/env python3
"""Vendor Claude Code plugin marketplaces for offline use.

For each marketplace in config/plugin-sources.json:
  * shallow-clone the repo and copy its working tree (no .git) to
    caches/claude-plugins/<marketplace-name>/
  * keep only plugins whose `source` is a relative path inside the repo;
    entries that point at other repos or URLs need a network and are dropped
  * disable remote-only MCP servers (http/sse with a URL) in kept plugins, in
    .mcp.json, plugin.json and the marketplace entry; stdio servers stay
  * drop plugins left with nothing to load once remote connectors are gone
  * write the rewritten marketplace.json, a VENDORED.md with what changed, and
    caches/claude-plugins/index.json for the install scripts

Usage: python scripts/vendor-plugins.py [repo-root]
"""
import json, os, shutil, subprocess, sys, tempfile, datetime

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..'))
CFG = json.load(open(os.path.join(ROOT, 'config', 'plugin-sources.json'), encoding='utf-8'))
OUT = os.path.join(ROOT, 'caches', 'claude-plugins')
COMPONENT_DIRS = ('skills', 'commands', 'agents', 'hooks', 'output-styles')


def load(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def save(p, obj):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write('\n')


def is_remote(server):
    return isinstance(server, dict) and bool(server.get('url')) and (server.get('type') in (None, 'http', 'sse', 'streamable-http'))


def split_servers(block):
    """Return (kept, removed) dicts from an mcpServers-like mapping."""
    servers = block.get('mcpServers', block) if isinstance(block, dict) else {}
    kept = {k: v for k, v in servers.items() if not is_remote(v)}
    removed = {k: v.get('url') for k, v in servers.items() if is_remote(v)}
    return kept, removed


def rmtree(path):
    def onerror(func, p, _):
        os.chmod(p, 0o700)
        func(p)
    shutil.rmtree(path, onerror=onerror)


def vendor(entry):
    repo, enable = entry['repo'], entry.get('enable', [])
    tmp = tempfile.mkdtemp(prefix='mkt-')
    try:
        subprocess.run(['git', 'clone', '-q', '--depth', '1', f'https://github.com/{repo}.git', tmp], check=True)
        sha = subprocess.run(['git', '-C', tmp, 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True).stdout.strip()
        mp = os.path.join(tmp, '.claude-plugin', 'marketplace.json')
        market = load(mp)
        upstream_name = market['name']
        if entry.get('name'):
            # upstream names under anthropics/ are reserved unless loaded from GitHub, so a local copy needs its own
            market['name'] = entry['name']
            market['description'] = f"Offline copy of {repo} (upstream marketplace '{upstream_name}'). " + (market.get('description') or market.get('metadata', {}).get('description', ''))
        name = market['name']
        dest = os.path.join(OUT, name)
        if os.path.exists(dest):
            rmtree(dest)
        shutil.copytree(tmp, dest, ignore=shutil.ignore_patterns('.git'))
    finally:
        rmtree(tmp)

    notes, kept_names, dropped_external, dropped_empty = [], [], [], []
    plugins = []
    for p in market.get('plugins', []):
        src = p.get('source')
        if not isinstance(src, str):
            dropped_external.append(p['name'])
            continue
        pdir = os.path.normpath(os.path.join(dest, src))
        if not os.path.isdir(pdir):
            dropped_external.append(p['name'])
            continue

        remaining_mcp = 0
        # .mcp.json in the plugin root
        mf = os.path.join(pdir, '.mcp.json')
        if os.path.exists(mf):
            kept, removed = split_servers(load(mf))
            if removed:
                if kept:
                    save(mf, {'mcpServers': kept})
                else:
                    os.replace(mf, mf + '.offline-disabled')
                notes.append(f"- `{p['name']}`: disabled remote MCP servers in .mcp.json: " + ', '.join(f'{k} ({u})' for k, u in removed.items()))
            remaining_mcp += len(kept)
        # plugin.json mcpServers
        pj = os.path.join(pdir, '.claude-plugin', 'plugin.json')
        manifest = load(pj) if os.path.exists(pj) else {}
        if isinstance(manifest.get('mcpServers'), dict):
            kept, removed = split_servers(manifest['mcpServers'])
            if removed:
                if kept:
                    manifest['mcpServers'] = kept
                else:
                    manifest.pop('mcpServers')
                save(pj, manifest)
                notes.append(f"- `{p['name']}`: removed remote MCP servers from plugin.json: " + ', '.join(removed))
            remaining_mcp += len(kept)
        # inline mcpServers in the marketplace entry
        if isinstance(p.get('mcpServers'), dict):
            kept, removed = split_servers(p['mcpServers'])
            if removed:
                if kept:
                    p['mcpServers'] = kept
                else:
                    p.pop('mcpServers')
                notes.append(f"- `{p['name']}`: removed remote MCP servers from the marketplace entry: " + ', '.join(removed))
            remaining_mcp += len(kept)

        has_components = any(os.path.isdir(os.path.join(pdir, d)) for d in COMPONENT_DIRS)
        has_inline = any(k in p for k in ('commands', 'agents', 'skills', 'hooks', 'lspServers')) or any(k in manifest for k in ('commands', 'agents', 'skills', 'hooks', 'lspServers'))
        has_lsp = os.path.exists(os.path.join(pdir, '.lsp.json'))
        if not (has_components or has_inline or has_lsp or remaining_mcp):
            dropped_empty.append(p['name'])
            continue
        plugins.append(p)
        kept_names.append(p['name'])

    market['plugins'] = plugins
    save(os.path.join(dest, '.claude-plugin', 'marketplace.json'), market)

    missing = [e for e in enable if e not in kept_names]
    if missing:
        raise SystemExit(f'{repo}: plugins to enable are not available offline: {missing}')

    lic = next((f for f in os.listdir(dest) if f.upper().startswith('LICENSE')), None)
    with open(os.path.join(dest, 'VENDORED.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(f'# Vendored copy of {repo}\n\n')
        f.write(f'Commit `{sha}`, taken {datetime.date.today().isoformat()} by scripts/vendor-plugins.py. ')
        f.write(f'Upstream license: {lic or "see upstream"}. Changes from upstream are listed below; nothing else was modified.\n\n')
        f.write(f'## Kept ({len(kept_names)})\n\n' + ', '.join(kept_names) + '\n\n')
        f.write(f'## Dropped, need a network to fetch ({len(dropped_external)})\n\n' + (', '.join(dropped_external) or 'none') + '\n\n')
        f.write(f'## Dropped, only remote connectors ({len(dropped_empty)})\n\n' + (', '.join(dropped_empty) or 'none') + '\n\n')
        f.write('## Remote MCP servers disabled\n\n' + ('\n'.join(notes) or 'none') + '\n')

    print(f'{name:28s} kept {len(kept_names):3d}  dropped-external {len(dropped_external):3d}  dropped-empty {len(dropped_empty):2d}  mcp-edits {len(notes):2d}')
    return {'name': name, 'upstream': upstream_name, 'dir': name, 'repo': repo, 'commit': sha, 'license': lic, 'plugins': kept_names, 'enable': enable}


def main():
    os.makedirs(OUT, exist_ok=True)
    for d in os.listdir(OUT):
        p = os.path.join(OUT, d)
        if os.path.isdir(p):
            rmtree(p)
    index = [vendor(m) for m in CFG['marketplaces']]
    save(os.path.join(OUT, 'index.json'), {'marketplaces': index})
    total = sum(len(m['plugins']) for m in index)
    print(f'{len(index)} marketplaces, {total} plugins available offline, {sum(len(m["enable"]) for m in index)} enabled by default')


if __name__ == '__main__':
    main()
