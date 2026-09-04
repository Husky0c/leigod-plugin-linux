#!/bin/sh
set -eu

umask 077

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$REPO_DIR/release.env"

CHECKSUM_FILE=${LEIGOD_CHECKSUM_FILE:-$REPO_DIR/checksums.sha256}
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/leigod-plugin-deb.XXXXXX")
OUTPUT=$REPO_DIR/packages/leigod-plugin_${PACKAGE_VERSION}_amd64.deb
OUTPUT_TMP=$OUTPUT.tmp.$$

cleanup() {
    rm -rf "$BUILD_DIR"
    rm -f "$OUTPUT_TMP"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

command -v dpkg-deb >/dev/null 2>&1 || {
    echo "[ERROR] dpkg-deb is required" >&2
    exit 1
}

install -d -m 0755 \
    "$BUILD_DIR/DEBIAN" \
    "$BUILD_DIR/lib/systemd/system" \
    "$BUILD_DIR/opt/leigod/config" \
    "$BUILD_DIR/usr/share/doc/leigod-plugin"

LEIGOD_CHECKSUM_FILE=$CHECKSUM_FILE \
    sh "$REPO_DIR/scripts/fetch-assets.sh" "$BUILD_DIR/opt/leigod"

install -m 0755 "$REPO_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$BUILD_DIR/opt/leigod/"
install -m 0755 "$REPO_DIR/opt/leigod/leigod_uninstall.sh" "$BUILD_DIR/opt/leigod/"
install -m 0755 "$REPO_DIR/scripts/device-mac.sh" "$BUILD_DIR/opt/leigod/"
install -m 0644 "$REPO_DIR/opt/leigod/fake_os-release" "$BUILD_DIR/opt/leigod/"
install -m 0644 "$REPO_DIR/opt/leigod/fake_product_name" "$BUILD_DIR/opt/leigod/"
install -m 0644 "$REPO_DIR/opt/leigod/config/acc_version.ini" "$BUILD_DIR/opt/leigod/config/"
install -m 0644 "$REPO_DIR/opt/leigod/config/new_upgrade_conf.json" "$BUILD_DIR/opt/leigod/config/"
install -m 0644 "$REPO_DIR/opt/leigod/config/accelerator.ini" "$BUILD_DIR/opt/leigod/config/"
: > "$BUILD_DIR/opt/leigod/config/accelerator"
chmod 0644 "$BUILD_DIR/opt/leigod/config/accelerator"

install -m 0644 "$REPO_DIR/systemd/leigod_plugin.service" "$BUILD_DIR/lib/systemd/system/"
install -m 0644 "$CHECKSUM_FILE" "$BUILD_DIR/usr/share/doc/leigod-plugin/checksums.sha256"
install -m 0644 "$REPO_DIR/LICENSE" "$BUILD_DIR/usr/share/doc/leigod-plugin/copyright"
install -m 0644 "$REPO_DIR/THIRD_PARTY_NOTICES.md" "$BUILD_DIR/usr/share/doc/leigod-plugin/"

for control_file in control preinst postinst prerm postrm; do
    install -m 0755 "$REPO_DIR/debian/$control_file" "$BUILD_DIR/DEBIAN/$control_file"
done
chmod 0644 "$BUILD_DIR/DEBIAN/control"

export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C
find "$BUILD_DIR" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
dpkg-deb --root-owner-group --build "$BUILD_DIR" "$OUTPUT_TMP"
mv -f "$OUTPUT_TMP" "$OUTPUT"
echo "Built reproducibly: $OUTPUT"
