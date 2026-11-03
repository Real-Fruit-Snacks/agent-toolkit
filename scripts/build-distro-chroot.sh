#!/usr/bin/env bash
# Builds wsl/ubuntu-dev.tar.gz on a plain Linux host (no WSL), for CI.
# Extracts the Ubuntu WSL rootfs, runs wsl-provision.sh inside a chroot with
# the toolkit mounted at /mnt/toolkit, then tars the result. `wsl --import`
# accepts the output exactly like the export bake-wsl.ps1 produces.
#   sudo bash scripts/build-distro-chroot.sh [dev-user]
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_USER="${1:-dev}"
ROOTFS=$(ls "$ROOT"/wsl/ubuntu-*-wsl-amd64-*.rootfs.tar.gz | head -1)
OUT="$ROOT/wsl/ubuntu-dev.tar.gz"
CH="${CHROOT_DIR:-/tmp/ubuntu-dev-rootfs}"

echo "== extracting $(basename "$ROOTFS") to $CH"
rm -rf "$CH"; mkdir -p "$CH"
tar -xzf "$ROOTFS" -C "$CH"

echo "== mounts"
mkdir -p "$CH/mnt/toolkit"
mount --bind "$ROOT" "$CH/mnt/toolkit"
mount -t proc proc "$CH/proc"
mount --rbind /sys "$CH/sys"; mount --make-rslave "$CH/sys"
mount --rbind /dev "$CH/dev"; mount --make-rslave "$CH/dev"
cp /etc/resolv.conf "$CH/etc/resolv.conf"
cleanup() {
  umount -R "$CH/dev" 2>/dev/null || true
  umount -R "$CH/sys" 2>/dev/null || true
  umount "$CH/proc" 2>/dev/null || true
  umount "$CH/mnt/toolkit" 2>/dev/null || true
}
trap cleanup EXIT

echo "== provisioning in chroot"
chroot "$CH" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive \
  bash /mnt/toolkit/scripts/wsl-provision.sh /mnt/toolkit "$DEV_USER"

echo "== cleaning"
chroot "$CH" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin bash -c 'apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache; rm -f /root/.bash_history /home/*/.bash_history'
# the host's resolv.conf must not ship; WSL generates its own
rm -f "$CH/etc/resolv.conf"
cleanup; trap - EXIT
rmdir "$CH/mnt/toolkit" 2>/dev/null || true

echo "== secret scan"
if find "$CH/home" "$CH/root" -maxdepth 3 \( -name '.credentials.json' -o -name 'hosts.yml' -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -name '.bash_history' -o -name '.netrc' -o -name '.git-credentials' \) -type f | grep .; then
  echo "credential-looking files found in the distro; aborting"; exit 1
fi

echo "== packing $OUT"
rm -f "$OUT"
tar -C "$CH" --numeric-owner --xattrs -czf "$OUT" .
rm -rf "$CH"
ls -la "$OUT"
