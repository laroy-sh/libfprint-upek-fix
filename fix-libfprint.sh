#!/usr/bin/env bash
# Fix UPEK TouchStrip (0483:2016) fingerprint verify on Ubuntu 24.04
# Backports upstream commit cdc22b45 to the Ubuntu libfprint package.
#
# Bugs fixed:
#   1. wrong buffer in verify_start_sm_run_state (data/data_len -> msg/msg_len)
#   2. inverted error condition in do_verify_stop
#
# Usage: bash fix-libfprint.sh
set -e

WORKDIR="$HOME/libfprint-fix"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "==> Installing build dependencies..."
sudo apt install -y \
    dpkg-dev devscripts build-essential debhelper \
    libglib2.0-dev libgusb-dev libgudev-1.0-dev \
    libnss3-dev gi-docgen \
    gir1.2-gusb-1.0 gobject-introspection \
    libgirepository1.0-dev \
    gtk-doc-tools libcairo2-dev umockdev libglib2.0-doc libgusb-doc

echo "==> Enabling deb-src in ubuntu.sources..."
sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
sudo apt update -q

echo "==> Downloading libfprint source package..."
apt source libfprint

# Find extracted source directory
SRCDIR=$(ls -d libfprint-*/ | head -1)
echo "==> Source directory: $SRCDIR"
cd "$SRCDIR"

echo "==> Applying fix 1: wrong buffer in verify_start_sm_run_state..."
sed -i 's/alloc_send_cmd28_transfer (dev, 0x03, data, data_len)/alloc_send_cmd28_transfer (dev, 0x03, msg, msg_len)/' \
    libfprint/drivers/upekts.c

echo "==> Applying fix 2: inverted error condition in do_verify_stop..."
sed -i 's/if (error && error->domain == FP_DEVICE_RETRY)/if (!error || error->domain == FP_DEVICE_RETRY)/' \
    libfprint/drivers/upekts.c

echo "==> Verifying patches were applied..."
grep -n "alloc_send_cmd28_transfer.*msg, msg_len" libfprint/drivers/upekts.c \
    || { echo "FAIL: fix 1 not applied"; exit 1; }
grep -n "if (!error || error->domain" libfprint/drivers/upekts.c \
    || { echo "FAIL: fix 2 not applied"; exit 1; }
echo "Both fixes applied successfully."

echo "==> Building .deb package (this will take a few minutes)..."
DEB_BUILD_OPTIONS="nocheck notest nodoc" dpkg-buildpackage -us -uc -b -j$(nproc)

cd "$WORKDIR"
echo "==> Installing built packages..."
sudo dpkg -i libfprint-2-2_*.deb libfprint-2-tod1_*.deb

echo "==> Checking library dependencies..."
ldd /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep "not found" && { echo "FAIL: missing library dependencies — rollback with dpkg -i ~/Projects/libfprint-upek-fix/rollback/*.deb"; exit 1; } || echo "Library dependencies OK."

echo "==> Holding packages to prevent auto-upgrade reversion..."
sudo apt-mark hold libfprint-2-2 libfprint-2-tod1

echo "==> Restoring ubuntu.sources (removing deb-src)..."
sudo sed -i 's/^Types: deb deb-src$/Types: deb/' /etc/apt/sources.list.d/ubuntu.sources
sudo apt update -q

echo "==> Restarting fprintd..."
sudo systemctl restart fprintd

echo ""
echo "Done! Test with: fprintd-verify \$(whoami)"
echo ""
echo "To clean up build dependencies afterwards:"
echo "  sudo apt remove --autoremove dpkg-dev devscripts build-essential \\"
echo "    libglib2.0-dev libgusb-dev libgudev-1.0-dev libnss3-dev gi-docgen \\"
echo "    gir1.2-gusb-1.0 gobject-introspection libgirepository1.0-dev"
echo ""
echo "Rollback (if GUI login breaks): sudo dpkg -i ~/Projects/libfprint-upek-fix/rollback/*.deb && sudo systemctl restart fprintd"
