#!/bin/sh
set -eu

umask 077

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$REPO_DIR/release.env"

CHECKSUM_FILE=${LEIGOD_CHECKSUM_FILE:-$REPO_DIR/checksums.sha256}
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-plugin-tar.XXXXXX")
PACKAGE_NAME=leigod-plugin-$PACKAGE_VERSION
PACKAGE_ROOT=$BUILD_ROOT/$PACKAGE_NAME
OUTPUT=$REPO_DIR/packages/leigod-plugin_${PACKAGE_VERSION}_amd64.tar.gz
OUTPUT_TMP=$OUTPUT.tmp.$$

cleanup() {
    rm -rf "$BUILD_ROOT"
    rm -f "$OUTPUT_TMP"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

install -d -m 0755 \
    "$PACKAGE_ROOT/opt/leigod/config" \
    "$PACKAGE_ROOT/scripts" \
    "$PACKAGE_ROOT/systemd"

LEIGOD_CHECKSUM_FILE=$CHECKSUM_FILE \
    sh "$REPO_DIR/scripts/fetch-assets.sh" "$PACKAGE_ROOT/opt/leigod"

install -m 0755 "$REPO_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$PACKAGE_ROOT/opt/leigod/"
install -m 0755 "$REPO_DIR/opt/leigod/leigod_uninstall.sh" "$PACKAGE_ROOT/opt/leigod/"
install -m 0755 "$REPO_DIR/scripts/device-mac.sh" "$PACKAGE_ROOT/scripts/"
install -m 0755 "$REPO_DIR/scripts/fetch-assets.sh" "$PACKAGE_ROOT/scripts/"
install -m 0644 "$REPO_DIR/opt/leigod/fake_os-release" "$PACKAGE_ROOT/opt/leigod/"
install -m 0644 "$REPO_DIR/opt/leigod/fake_product_name" "$PACKAGE_ROOT/opt/leigod/"
install -m 0644 "$REPO_DIR/opt/leigod/config/acc_version.ini" "$PACKAGE_ROOT/opt/leigod/config/"
install -m 0644 "$REPO_DIR/opt/leigod/config/new_upgrade_conf.json" "$PACKAGE_ROOT/opt/leigod/config/"
install -m 0644 "$REPO_DIR/opt/leigod/config/accelerator.ini" "$PACKAGE_ROOT/opt/leigod/config/"
: > "$PACKAGE_ROOT/opt/leigod/config/accelerator"
chmod 0644 "$PACKAGE_ROOT/opt/leigod/config/accelerator"

install -m 0755 "$REPO_DIR/install.sh" "$PACKAGE_ROOT/"
install -m 0755 "$REPO_DIR/uninstall.sh" "$PACKAGE_ROOT/"
install -m 0644 "$CHECKSUM_FILE" "$PACKAGE_ROOT/checksums.sha256"
install -m 0644 "$REPO_DIR/release.env" "$PACKAGE_ROOT/"
install -m 0644 "$REPO_DIR/systemd/leigod_plugin.service" "$PACKAGE_ROOT/systemd/"
install -m 0644 "$REPO_DIR/README.md" "$PACKAGE_ROOT/"
install -m 0644 "$REPO_DIR/LICENSE" "$PACKAGE_ROOT/"
install -m 0644 "$REPO_DIR/THIRD_PARTY_NOTICES.md" "$PACKAGE_ROOT/"

export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C
find "$PACKAGE_ROOT" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
tar --sort=name --format=gnu --owner=0 --group=0 --numeric-owner \
    --mtime="@$SOURCE_DATE_EPOCH" -C "$BUILD_ROOT" -cf - "$PACKAGE_NAME" \
    | gzip -n > "$OUTPUT_TMP"
mv -f "$OUTPUT_TMP" "$OUTPUT"
echo "Built reproducibly: $OUTPUT"
