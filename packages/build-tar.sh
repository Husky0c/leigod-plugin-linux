#!/bin/sh
set -e

REPO_DIR="$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)"
OUTPUT="$REPO_DIR/packages/leigod-plugin_1.2.2.15_amd64.tar.gz"
TMPDIR="/tmp/opencode/leigod-plugin-tar"
PACKAGE_ROOT="$TMPDIR/leigod-plugin-1.2.2.15"

rm -rf "$TMPDIR"
mkdir -p "$PACKAGE_ROOT/opt/leigod/config" "$PACKAGE_ROOT/scripts"

# Download both assets, verify pinned SHA-256 values, then install atomically.
LEIGOD_CHECKSUM_FILE=${LEIGOD_CHECKSUM_FILE:-$REPO_DIR/checksums.sha256} \
    sh "$REPO_DIR/scripts/fetch-assets.sh" "$PACKAGE_ROOT/opt/leigod"

# Copy files
cp "$REPO_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$PACKAGE_ROOT/opt/leigod/"
cp "$REPO_DIR/opt/leigod/leigod_uninstall.sh" "$PACKAGE_ROOT/opt/leigod/"
cp "$REPO_DIR/opt/leigod/fake_os-release" "$PACKAGE_ROOT/opt/leigod/"
cp "$REPO_DIR/opt/leigod/fake_product_name" "$PACKAGE_ROOT/opt/leigod/"
cp "$REPO_DIR/opt/leigod/config/acc_version.ini" "$PACKAGE_ROOT/opt/leigod/config/"
cp "$REPO_DIR/opt/leigod/config/new_upgrade_conf.json" "$PACKAGE_ROOT/opt/leigod/config/"
cp "$REPO_DIR/opt/leigod/config/accelerator.ini" "$PACKAGE_ROOT/opt/leigod/config/"
touch "$PACKAGE_ROOT/opt/leigod/config/accelerator"
cp "$REPO_DIR/install.sh" "$PACKAGE_ROOT/"
cp "$REPO_DIR/uninstall.sh" "$PACKAGE_ROOT/"
cp "$REPO_DIR/checksums.sha256" "$PACKAGE_ROOT/"
cp "$REPO_DIR/scripts/fetch-assets.sh" "$PACKAGE_ROOT/scripts/"

# Permissions
chmod 755 "$PACKAGE_ROOT/install.sh" "$PACKAGE_ROOT/uninstall.sh"
chmod 755 "$PACKAGE_ROOT/scripts/fetch-assets.sh"
chmod 755 "$PACKAGE_ROOT/opt/leigod/acc-gw.router.amd64" "$PACKAGE_ROOT/opt/leigod/acc_upgrade_monitor"
chmod 755 "$PACKAGE_ROOT/opt/leigod/steamdeck_acc_monitor.sh" "$PACKAGE_ROOT/opt/leigod/leigod_uninstall.sh"

cd "$TMPDIR" && tar czf "$OUTPUT" "leigod-plugin-1.2.2.15/"
rm -rf "$TMPDIR"
echo "Built: $OUTPUT"
