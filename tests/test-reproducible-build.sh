#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$REPO_DIR/release.env"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-build-test.XXXXXX")
TAR_OUTPUT=$REPO_DIR/packages/leigod-plugin_${PACKAGE_VERSION}_amd64.tar.gz
DEB_OUTPUT=$REPO_DIR/packages/leigod-plugin_${PACKAGE_VERSION}_amd64.deb
trap 'rm -rf "$TEST_ROOT"; rm -f "$TAR_OUTPUT" "$DEB_OUTPUT"' 0 HUP INT TERM

FIXTURES=$TEST_ROOT/fixtures
mkdir -p "$FIXTURES/config"
printf 'fixture gateway\n' > "$FIXTURES/acc-gw.router.amd64"
printf 'fixture database\n' > "$FIXTURES/config/ipdatacloud_country.xdb"
acc_hash=$(sha256sum "$FIXTURES/acc-gw.router.amd64" | awk '{print $1}')
xdb_hash=$(sha256sum "$FIXTURES/config/ipdatacloud_country.xdb" | awk '{print $1}')
printf '%s  %s\n%s  %s\n' \
    "$acc_hash" acc-gw.router.amd64 \
    "$xdb_hash" ipdatacloud_country.xdb \
    > "$TEST_ROOT/checksums.sha256"

LEIGOD_ASSET_SOURCE_DIR=$FIXTURES LEIGOD_CHECKSUM_FILE=$TEST_ROOT/checksums.sha256 \
    sh "$REPO_DIR/packages/build-tar.sh"
cp "$TAR_OUTPUT" "$TEST_ROOT/first.tar.gz"
sleep 1
LEIGOD_ASSET_SOURCE_DIR=$FIXTURES LEIGOD_CHECKSUM_FILE=$TEST_ROOT/checksums.sha256 \
    sh "$REPO_DIR/packages/build-tar.sh"
cmp "$TEST_ROOT/first.tar.gz" "$TAR_OUTPUT"
tar -tzf "$TAR_OUTPUT" | grep -q "leigod-plugin-$PACKAGE_VERSION/THIRD_PARTY_NOTICES.md"

if command -v dpkg-deb >/dev/null 2>&1; then
    LEIGOD_ASSET_SOURCE_DIR=$FIXTURES LEIGOD_CHECKSUM_FILE=$TEST_ROOT/checksums.sha256 \
        sh "$REPO_DIR/packages/build-deb.sh"
    cp "$DEB_OUTPUT" "$TEST_ROOT/first.deb"
    sleep 1
    LEIGOD_ASSET_SOURCE_DIR=$FIXTURES LEIGOD_CHECKSUM_FILE=$TEST_ROOT/checksums.sha256 \
        sh "$REPO_DIR/packages/build-deb.sh"
    cmp "$TEST_ROOT/first.deb" "$DEB_OUTPUT"
    dpkg-deb --info "$DEB_OUTPUT" >/dev/null
fi
echo "reproducible-build tests passed"
