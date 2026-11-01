#!/usr/bin/env bash
# Standalone Linux (Debian/Ubuntu) install. Installs T3 Code from the .deb and
# provisions the rest with wsl-provision.sh, which is distro-agnostic.
#   sudo bash scripts/install-linux.sh [username]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="${1:-${SUDO_USER:-$USER}}"

DEB=$(ls "$ROOT"/linux/T3-Code-*-amd64.deb | head -1)
echo "== Installing $(basename "$DEB")"
dpkg -i "$DEB" || apt-get -f install -y

bash "$ROOT/scripts/wsl-provision.sh" "$ROOT" "$USER_NAME"

echo
echo "T3 Code installed. Launch 't3-code' or the desktop entry."
echo "Headless alternative: tar -xzf linux/t3-*-linux-x64.tar.gz and run ./t3"
