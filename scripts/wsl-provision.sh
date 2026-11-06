#!/usr/bin/env bash
# Provisions an Ubuntu WSL distro (or any Debian-based box) from the toolkit's
# linux/ and caches/ folders. Runs fully offline when given the repo path.
#
#   sudo bash scripts/wsl-provision.sh /mnt/c/path/to/agent-toolkit [username]
#
# With network access (used by bake-wsl.ps1) it also apt-installs git and
# build essentials. Offline it skips apt and relies on what the rootfs has.
set -euo pipefail

ROOT="${1:?path to agent-toolkit repo}"
DEV_USER="${2:-dev}"
LINUX="$ROOT/linux"
CACHES="$ROOT/caches"

log() { printf '\n== %s\n' "$*"; }

ONLINE=0
if timeout 5 bash -c 'exec 3<>/dev/tcp/archive.ubuntu.com/80' 2>/dev/null; then ONLINE=1; fi

if [ "$ONLINE" = 1 ]; then
  log "apt packages (online)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq git curl ca-certificates unzip xz-utils build-essential python3 \
    libnss3 libatk-bridge2.0-0 libdrm2 libxkbcommon0 libgbm1 libasound2t64 libxcomposite1 \
    libxdamage1 libxrandr2 libpango-1.0-0 libcairo2 libcups2 >/dev/null
else
  log "offline: skipping apt (git/curl must already be in the rootfs)"
fi

log "user $DEV_USER"
if ! id "$DEV_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo "$DEV_USER"
  echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$DEV_USER
  chmod 0440 /etc/sudoers.d/90-$DEV_USER
fi
HOME_DIR=$(getent passwd "$DEV_USER" | cut -d: -f6)

log "Node.js"
NODE_TAR=$(ls "$LINUX"/node-v*-linux-x64.tar.xz | head -1)
NODE_VER=$(basename "$NODE_TAR" | sed -E 's/node-(v[0-9.]+)-.*/\1/')
mkdir -p /opt/node
tar -xJf "$NODE_TAR" -C /opt/node
ln -sfn "/opt/node/node-$NODE_VER-linux-x64" /opt/node/current
for b in node npm npx corepack; do ln -sf /opt/node/current/bin/$b /usr/local/bin/$b; done

log "GitHub CLI"
GH_DEB=$(ls "$LINUX"/gh_*_linux_amd64.deb | head -1)
dpkg -i "$GH_DEB" >/dev/null || apt-get -f install -y -qq >/dev/null || true

log "Claude Code CLI"
CLAUDE_BIN=$(ls "$LINUX"/claude-code/claude-*-linux-x64 | grep -v musl | head -1)
CLAUDE_VER=$(cat "$LINUX/claude-code/VERSION")
install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.local/bin" "$HOME_DIR/.local/share/claude/versions"
install -m 0755 -o "$DEV_USER" -g "$DEV_USER" "$CLAUDE_BIN" "$HOME_DIR/.local/share/claude/versions/$CLAUDE_VER"
ln -sfn "$HOME_DIR/.local/share/claude/versions/$CLAUDE_VER" "$HOME_DIR/.local/bin/claude"
chown -h "$DEV_USER:$DEV_USER" "$HOME_DIR/.local/bin/claude"

log "T3 tool cache (linux)"
T3TOOLS="$HOME_DIR/.t3/tools"
install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.t3" "$T3TOOLS"
CHS_ZIP=$(ls "$CACHES"/t3-tools-linux/chrome-headless-shell/linux64/chrome-headless-shell-linux64-*.zip | head -1)
CHS_VER=$(basename "$CHS_ZIP" .zip | sed -E 's/.*linux64-//')
CHS_DIR="$T3TOOLS/chrome-headless-shell/linux64/$CHS_VER"
if [ ! -d "$CHS_DIR" ]; then
  mkdir -p "$CHS_DIR.tmp" && unzip -q "$CHS_ZIP" -d "$CHS_DIR.tmp"
  mv "$CHS_DIR.tmp/chrome-headless-shell-linux64" "$CHS_DIR" && rm -rf "$CHS_DIR.tmp"
fi
# agent-device / expo-device-hub: prefer the fully installed dirs (node_modules included) shipped in caches/t3-tools-linux
for pkg in agent-device expo-device-hub; do
  if [ -d "$CACHES/t3-tools-linux/$pkg" ]; then
    cp -r "$CACHES/t3-tools-linux/$pkg" "$T3TOOLS/"; continue
  fi
  TGZ=$(ls "$CACHES"/npm/$pkg-*.tgz 2>/dev/null | head -1) || continue
  VER=$(basename "$TGZ" .tgz | sed -E "s/^$pkg-//")
  DEST="$T3TOOLS/$pkg/$VER"
  if [ ! -f "$DEST/.install-complete" ]; then
    mkdir -p "$DEST"
    printf '{
  "dependencies": {
    "%s": "^%s"
  }
}
' "$pkg" "$VER" > "$DEST/package.json"
    (cd "$DEST" && npm install --no-audit --no-fund --omit=dev --offline --cache "$CACHES/npm-cache" "$pkg@$VER" >/dev/null) && touch "$DEST/.install-complete"       || echo "warn: $pkg install failed offline; T3 will retry when online"
  fi
done
chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/.t3"

log "Playwright browsers"
PW="$HOME_DIR/.cache/ms-playwright"
install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.cache" "$PW"
if [ -d "$CACHES/playwright-browsers-linux" ]; then
  cp -r "$CACHES"/playwright-browsers-linux/* "$PW"/ && chown -R "$DEV_USER:$DEV_USER" "$PW"
elif [ "$ONLINE" = 1 ]; then
  PW_TGZ=$(ls "$CACHES"/npm/playwright-[0-9]*.tgz | head -1)
  npm install -g --no-audit --no-fund "$PW_TGZ" >/dev/null 2>&1 || true
  if command -v playwright >/dev/null 2>&1 || [ -x /opt/node/current/bin/playwright ]; then
    sudo -u "$DEV_USER" env PLAYWRIGHT_BROWSERS_PATH="$PW" HOME="$HOME_DIR" PATH="/opt/node/current/bin:/usr/local/bin:$PATH" \
      playwright install chromium chromium-headless-shell 2>&1 | tail -3 \
      || echo "warn: playwright browser install failed; run it later or skip"
    ln -sf /opt/node/current/bin/playwright /usr/local/bin/playwright 2>/dev/null || true
  else
    echo "warn: playwright CLI not installed from $PW_TGZ"
  fi
  chown -R "$DEV_USER:$DEV_USER" "$PW"
fi

log "npm cache (offline installs)"
if [ -d "$CACHES/npm-cache" ]; then
  install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.npm-toolkit-cache"
  cp -r "$CACHES"/npm-cache/. "$HOME_DIR/.npm-toolkit-cache"/ && chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/.npm-toolkit-cache"
  for pkg in playwright @playwright/cli; do
    npm install -g --offline --cache "$HOME_DIR/.npm-toolkit-cache" --no-audit --no-fund "$pkg" >/dev/null 2>&1 || echo "warn: global $pkg install from cache failed"
  done
fi

log "Claude Code skills"
if [ -d "$CACHES/claude-skills" ]; then
  install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.claude" "$HOME_DIR/.claude/skills"
  for d in "$CACHES"/claude-skills/*/; do cp -r "$d" "$HOME_DIR/.claude/skills/"; done
  chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/.claude"
fi

log "killer-skills font pack (web fonts killer-design self-hosts)"
# Same folder and installed-sha256.txt marker as killer-skills' own install.sh. Its runtime is Windows only.
FONTS_TGZ="$CACHES/killer-skills/killer-skills-fonts.tar.gz"
if [ -f "$FONTS_TGZ" ]; then
  want=$(awk '$2 == "killer-skills-fonts.tar.gz" { print $1 }' "$CACHES/killer-skills/SHA256SUMS.txt")
  if [ -n "$want" ] && [ "$(sha256sum "$FONTS_TGZ" | cut -d' ' -f1)" = "$want" ]; then
    FONTS_DIR="$HOME_DIR/.cache/killer-skills-fonts"
    install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.cache"
    rm -rf "$FONTS_DIR" && mkdir -p "$FONTS_DIR"
    tar -xzf "$FONTS_TGZ" -C "$FONTS_DIR" && printf '%s\n' "$want" > "$FONTS_DIR/installed-sha256.txt"
    chown -R "$DEV_USER:$DEV_USER" "$FONTS_DIR"
  else
    echo "warn: killer-skills-fonts.tar.gz doesn't match caches/killer-skills/SHA256SUMS.txt; skipped"
  fi
fi

log "Python packages for the document skills"
if [ -d "$CACHES/pip-wheelhouse/linux" ] && [ "$ONLINE" = 1 ]; then
  apt-get install -y -qq python3-pip python3-venv >/dev/null 2>&1 || true
fi
if [ -d "$CACHES/pip-wheelhouse/linux" ]; then
  sudo -u "$DEV_USER" python3 -m venv "$HOME_DIR/.venv-skills" 2>/dev/null &&   sudo -u "$DEV_USER" "$HOME_DIR/.venv-skills/bin/pip" install --quiet --no-index --find-links "$CACHES/pip-wheelhouse/linux" -r "$CACHES/pip-wheelhouse/requirements.txt"     || echo "warn: wheelhouse install incomplete (python3-venv missing or a wheel absent); run it later"
fi

log "MCP servers"
MCP_JSON="$ROOT/config/mcp-servers.json"
if [ -f "$MCP_JSON" ] && command -v python3 >/dev/null 2>&1; then
  # npm servers (MCP + language servers for the LSP plugins) from the seeded cache, installed globally as root
  NPM_PKGS=$(python3 -c "import json,sys; m=json.load(open(sys.argv[1]))['servers']; l=json.load(open(sys.argv[2])).get('lsp',{}).get('npm',[]); print(' '.join([s['package'] for s in m if s['kind']=='npm' and ('linux' in s.get('platforms',['linux']))] + l))" "$MCP_JSON" "$ROOT/config/plugin-sources.json")
  if [ -d "$HOME_DIR/.npm-toolkit-cache" ] && [ -n "$NPM_PKGS" ]; then
    for pkg in $NPM_PKGS; do   # one at a time, so one unresolvable package doesn't block the rest
      npm install -g --offline --cache "$HOME_DIR/.npm-toolkit-cache" --no-audit --no-fund "$pkg" >/tmp/npm-mcp.log 2>&1         || echo "warn: npm $pkg did not install from the cache: $(grep -m1 -E 'npm error (code|request)' /tmp/npm-mcp.log)"
    done
  fi
  # python servers: one venv per server under ~/.venv-mcp/<id>, since they pin conflicting dependency versions
  if [ -d "$CACHES/pip-wheelhouse/linux" ]; then
    install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.venv-mcp"
    python3 -c "import json,sys; [print(s['id'], s['package'], s['bin']) for s in json.load(open(sys.argv[1]))['servers'] if s['kind']=='pip' and 'linux' in s.get('platforms',['linux'])]" "$MCP_JSON" | while read -r id pkg bin; do
      V="$HOME_DIR/.venv-mcp/$id"
      [ -x "$V/bin/$bin" ] && continue
      sudo -u "$DEV_USER" python3 -m venv "$V" 2>/dev/null && \
      sudo -u "$DEV_USER" "$V/bin/pip" install --quiet --disable-pip-version-check --no-index --find-links "$CACHES/pip-wheelhouse/linux" "$pkg" >/dev/null 2>&1 \
        || { echo "warn: MCP $id ($pkg) has no complete wheel set for this Python; skipped"; rm -rf "$V"; }
    done
  fi
  # release binaries (github-mcp-server, mcp-grafana, ...)
  python3 -c "import json,sys; [print(s['bin'], s['asset_linux']) for s in json.load(open(sys.argv[1]))['servers'] if s['kind']=='bin' and s.get('asset_linux')]" "$MCP_JSON" | while read -r bin asset; do
    A="$CACHES/mcp-bin/linux/$asset"
    [ -f "$A" ] || { echo "warn: missing $asset"; continue; }
    T=$(mktemp -d); tar -xzf "$A" -C "$T" 2>/dev/null
    F=$(find "$T" -type f -name "$bin" | head -1)
    [ -n "$F" ] && install -m 0755 -o "$DEV_USER" -g "$DEV_USER" "$F" "$HOME_DIR/.local/bin/$bin"
    rm -rf "$T"
  done
  # register defaults + write the catalog (same logic as install-mcp.ps1, in python)
  NPM_ROOT=$(npm root -g 2>/dev/null)
  sudo -u "$DEV_USER" env HOME="$HOME_DIR" python3 - "$MCP_JSON" "$HOME_DIR" "$NPM_ROOT" <<'PY'
import json, os, sys
man, home, npm_root = sys.argv[1], sys.argv[2], sys.argv[3]
servers = json.load(open(man))["servers"]
def ex(v): return str(v).replace("${HOME}", home).replace("${CWD}", ".")
installed = {}
for s in servers:
    if s["kind"] == "npm":
        pj = os.path.join(npm_root, s["package"], "package.json")
        if not os.path.exists(pj): continue
        b = json.load(open(pj)).get("bin")
        rel = b if isinstance(b, str) else (b.get(s["bin"]) or next(iter(b.values())))
        installed[s["id"]] = {"command": "node", "args": [os.path.join(npm_root, s["package"], rel)] + [ex(a) for a in s.get("args", [])]}
    elif s["kind"] == "pip":
        exe = os.path.join(home, ".venv-mcp", s["id"], "bin", s["bin"])
        if os.path.exists(exe): installed[s["id"]] = {"command": exe, "args": [ex(a) for a in s.get("args", [])]}
    elif s["kind"] == "bin":
        exe = os.path.join(home, ".local", "bin", s["bin"])
        if os.path.exists(exe): installed[s["id"]] = {"command": exe, "args": list(s.get("args", []))}
cj = os.path.join(home, ".claude.json")
cfg = json.load(open(cj)) if os.path.exists(cj) else {}
cfg.setdefault("mcpServers", {})
added = 0
for s in servers:
    if s["id"] not in installed or not s.get("default") or s["id"] in cfg["mcpServers"]: continue
    e = {"type": "stdio", **installed[s["id"]]}
    if s.get("env"): e["env"] = {k: ex(v) for k, v in s["env"].items()}
    cfg["mcpServers"][s["id"]] = e; added += 1
json.dump(cfg, open(cj, "w"), indent=2)
os.makedirs(os.path.join(home, "agent-toolkit-docs"), exist_ok=True)
lines = ["# Bundled MCP servers", "", "Installed by the toolkit. Default ones are already in your Claude Code user config. Add any other with the line shown, filling in placeholders.", ""]
for s in servers:
    if s["id"] not in installed: continue
    i = installed[s["id"]]
    envf = " ".join(f'-e {k}="{ex(v)}"' for k, v in (s.get("env") or {}).items())
    cmd = f'claude mcp add -s user {envf} {s["id"]} -- "{i["command"]}" ' + " ".join(f'"{a}"' for a in i["args"])
    lines += [f'## {s["id"]}' + (" (registered by default)" if s.get("default") else ""), "", s.get("note",""), "", "```", " ".join(cmd.split()), "```", ""]
open(os.path.join(home, "agent-toolkit-docs", "mcp-servers.md"), "w").write("\n".join(lines))
print(f"registered {added} default MCP server(s); {len(installed)} installed")
PY
  chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/.claude.json" "$HOME_DIR/agent-toolkit-docs" 2>/dev/null || true
fi

log "Claude Code plugins (vendored marketplaces, offline)"
if [ -f "$CACHES/claude-plugins/index.json" ]; then
  sudo -u "$DEV_USER" env HOME="$HOME_DIR" PATH="$HOME_DIR/.local/bin:/opt/node/current/bin:/usr/local/bin:/usr/bin:/bin" \
    DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    python3 "$ROOT/scripts/install-plugins.py" --repo "$ROOT" --claude "$HOME_DIR/.local/bin/claude" --skip-lsp-npm \
    || echo "warn: plugin install reported problems; run scripts/install-plugins.py again as $DEV_USER"
fi

log "Claude Code config seed (no account data)"
install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.claude"
# merge, don't skip: the MCP and plugin steps above may already have created these files
sudo -u "$DEV_USER" python3 - "$ROOT/config/claude-home" "$HOME_DIR" <<'PY'
import json, os, sys
seeds, home = sys.argv[1], sys.argv[2]
for seed, target in (("claude.json.example", os.path.join(home, ".claude.json")), ("settings.json.example", os.path.join(home, ".claude", "settings.json"))):
    s = json.load(open(os.path.join(seeds, seed)))
    cur = json.load(open(target)) if os.path.exists(target) else {}
    for k, v in s.items():
        if k != "$comment":
            cur.setdefault(k, v)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    json.dump(cur, open(target, "w"), indent=2)
PY

log "offline docs"
install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/agent-toolkit-docs"
[ -d "$CACHES/claude-code-docs" ] && cp -r "$CACHES/claude-code-docs" "$HOME_DIR/agent-toolkit-docs/claude-code"
[ -d "$ROOT/docs/reference/t3code" ] && cp -r "$ROOT/docs/reference/t3code" "$HOME_DIR/agent-toolkit-docs/t3code"
chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/agent-toolkit-docs"

log "environment"
cat > /etc/profile.d/agent-toolkit.sh <<'EOF'
export T3CODE_DISABLE_AUTO_UPDATE=1
export T3CODE_TELEMETRY_ENABLED=0
export T3CODE_OTEL_SDK_DISABLED=1
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/ms-playwright"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export npm_config_cache="$HOME/.npm-toolkit-cache"
export npm_config_offline=true
[ -d "$HOME/.venv-skills" ] && case ":$PATH:" in *":$HOME/.venv-skills/bin:"*) ;; *) export PATH="$HOME/.venv-skills/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
EOF

cat > /etc/wsl.conf <<EOF
[user]
default=$DEV_USER
[boot]
systemd=true
EOF

log "done"
echo "claude: $(sudo -u "$DEV_USER" "$HOME_DIR/.local/bin/claude" --version 2>/dev/null || echo 'not runnable yet')"
echo "node:   $(node --version)   gh: $(gh --version | head -1)   git: $(git --version)"
