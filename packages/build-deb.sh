#!/bin/sh
set -e

REPO_DIR="$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/opencode/leigod-plugin-build"
OUTPUT="$REPO_DIR/packages/leigod-plugin_1.2.2.15_amd64.deb"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN" "$BUILD_DIR/opt/leigod/config" "$BUILD_DIR/usr/share/doc/leigod-plugin"

# Download both assets, verify pinned SHA-256 values, then install atomically.
LEIGOD_CHECKSUM_FILE=${LEIGOD_CHECKSUM_FILE:-$REPO_DIR/checksums.sha256} \
    sh "$REPO_DIR/scripts/fetch-assets.sh" "$BUILD_DIR/opt/leigod"

# Copy files
cp "$REPO_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$BUILD_DIR/opt/leigod/"
cp "$REPO_DIR/opt/leigod/leigod_uninstall.sh" "$BUILD_DIR/opt/leigod/"
cp "$REPO_DIR/opt/leigod/fake_os-release" "$BUILD_DIR/opt/leigod/"
cp "$REPO_DIR/opt/leigod/fake_product_name" "$BUILD_DIR/opt/leigod/"
cp "$REPO_DIR/opt/leigod/config/acc_version.ini" "$BUILD_DIR/opt/leigod/config/"
cp "$REPO_DIR/opt/leigod/config/new_upgrade_conf.json" "$BUILD_DIR/opt/leigod/config/"
cp "$REPO_DIR/opt/leigod/config/accelerator.ini" "$BUILD_DIR/opt/leigod/config/"
cp "$REPO_DIR/checksums.sha256" "$BUILD_DIR/usr/share/doc/leigod-plugin/"
touch "$BUILD_DIR/opt/leigod/config/accelerator"

# Debian control files
cp "$REPO_DIR/debian/control" "$BUILD_DIR/DEBIAN/"
cp "$REPO_DIR/debian/preinst" "$BUILD_DIR/DEBIAN/"
cp "$REPO_DIR/debian/postinst" "$BUILD_DIR/DEBIAN/"
cp "$REPO_DIR/debian/prerm" "$BUILD_DIR/DEBIAN/"
cp "$REPO_DIR/debian/postrm" "$BUILD_DIR/DEBIAN/"

# Permissions
chmod 755 "$BUILD_DIR/DEBIAN/preinst" "$BUILD_DIR/DEBIAN/postinst"
chmod 755 "$BUILD_DIR/DEBIAN/prerm" "$BUILD_DIR/DEBIAN/postrm"
chmod 755 "$BUILD_DIR/opt/leigod/acc-gw.router.amd64" "$BUILD_DIR/opt/leigod/acc_upgrade_monitor"
chmod 755 "$BUILD_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$BUILD_DIR/opt/leigod/leigod_uninstall.sh"

fakeroot dpkg-deb --build "$BUILD_DIR" "$OUTPUT"
rm -rf "$BUILD_DIR"
echo "Built: $OUTPUT"
