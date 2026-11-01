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
  npm install -g --offline --cache "$HOME_DIR/.npm-toolkit-cache" --no-audit --no-fund playwright @playwright/cli >/dev/null 2>&1 || echo "warn: global playwright install from cache failed"
fi

log "Claude Code skills"
if [ -d "$CACHES/claude-skills" ]; then
  install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.claude" "$HOME_DIR/.claude/skills"
  for d in "$CACHES"/claude-skills/*/; do cp -r "$d" "$HOME_DIR/.claude/skills/"; done
  chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/.claude"
fi

log "Python packages for the document skills"
if [ -d "$CACHES/pip-wheelhouse/linux" ] && [ "$ONLINE" = 1 ]; then
  apt-get install -y -qq python3-pip python3-venv >/dev/null 2>&1 || true
fi
if [ -d "$CACHES/pip-wheelhouse/linux" ]; then
  sudo -u "$DEV_USER" python3 -m venv "$HOME_DIR/.venv-skills" 2>/dev/null &&   sudo -u "$DEV_USER" "$HOME_DIR/.venv-skills/bin/pip" install --quiet --no-index --find-links "$CACHES/pip-wheelhouse/linux" -r "$CACHES/pip-wheelhouse/requirements.txt"     || echo "warn: wheelhouse install incomplete (python3-venv missing or a wheel absent); run it later"
fi

log "Claude Code config seed (no account data)"
install -d -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.claude"
if [ ! -f "$HOME_DIR/.claude.json" ]; then
  python3 - "$ROOT/config/claude-home/claude.json.example" "$HOME_DIR/.claude.json" <<'PY' 2>/dev/null || cp "$ROOT/config/claude-home/claude.json.example" "$HOME_DIR/.claude.json"
import json,sys; d=json.load(open(sys.argv[1])); d.pop("$comment",None); json.dump(d,open(sys.argv[2],"w"),indent=2)
PY
  chown "$DEV_USER:$DEV_USER" "$HOME_DIR/.claude.json"
fi
[ -f "$HOME_DIR/.claude/settings.json" ] || { cp "$ROOT/config/claude-home/settings.json.example" "$HOME_DIR/.claude/settings.json"; chown "$DEV_USER:$DEV_USER" "$HOME_DIR/.claude/settings.json"; }

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
