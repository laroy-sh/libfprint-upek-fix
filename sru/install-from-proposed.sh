#!/usr/bin/env bash
# Install libfprint 1:1.94.7+tod1-0ubuntu5~24.04.9 from noble-proposed for
# SRU verification of LP #2145103. noble-proposed is only enabled long enough
# to install the two packages, then it is removed again.
#
# Usage: sudo bash sru/install-from-proposed.sh
#
# Rollback to the locally patched build:
#   sudo dpkg -i ~/libfprint-fix/libfprint-2-2_*.deb ~/libfprint-fix/libfprint-2-tod1_*.deb
#   sudo apt-mark hold libfprint-2-2 libfprint-2-tod1
set -euo pipefail

VERSION="1:1.94.7+tod1-0ubuntu5~24.04.9"
SRC=/etc/apt/sources.list.d/ubuntu-proposed-lp2145103.sources
PIN=/etc/apt/preferences.d/ubuntu-proposed-lp2145103

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

cleanup() {
    rm -f "$SRC" "$PIN"
    apt-get update -q >/dev/null || true
}
trap cleanup EXIT

echo "==> Enabling noble-proposed (pinned to 100, no automatic upgrades)..."
cat > "$SRC" <<EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble-proposed
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
cat > "$PIN" <<EOF
Package: *
Pin: release a=noble-proposed
Pin-Priority: 100
EOF
apt-get update -q

echo "==> Installing $VERSION..."
apt-mark unhold libfprint-2-2 libfprint-2-tod1
apt-get install -y "libfprint-2-2=$VERSION" "libfprint-2-tod1=$VERSION"

for p in libfprint-2-2 libfprint-2-tod1; do
    v=$(dpkg-query -W -f='${Version}' "$p")
    [ "$v" = "$VERSION" ] || { echo "FAIL: $p is $v, expected $VERSION"; exit 1; }
done

echo "==> Checking library dependencies..."
if ldd /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep "not found"; then
    echo "FAIL: missing library dependencies (see rollback in header)"; exit 1
fi

echo "==> Restarting fprintd..."
systemctl restart fprintd || true

echo "==> Removing noble-proposed again..."
cleanup
trap - EXIT

dpkg -l libfprint-2-2 libfprint-2-tod1 | tail -2
echo
echo "Done. Packages are not held: noble-updates only has an older version,"
echo "and the hold would otherwise block the eventual release/security updates."
echo "Next, as your normal user: bash sru/run-verification.sh"
