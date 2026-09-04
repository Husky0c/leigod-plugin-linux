#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-fetch-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' 0
trap 'exit 1' HUP INT TERM

SOURCE_DIR=$TEST_ROOT/source
DEST_DIR=$TEST_ROOT/destination
CHECKSUM_FILE=$TEST_ROOT/checksums.sha256
mkdir -p "$SOURCE_DIR/config" "$DEST_DIR/config"

printf 'verified executable fixture\n' > "$SOURCE_DIR/acc-gw.router.amd64"
printf 'verified xdb fixture\n' > "$SOURCE_DIR/config/ipdatacloud_country.xdb"
(
    cd "$SOURCE_DIR"
    sha256sum acc-gw.router.amd64 config/ipdatacloud_country.xdb \
        | sed 's#  config/#  #'
) > "$CHECKSUM_FILE"

LEIGOD_ASSET_SOURCE_DIR=$SOURCE_DIR \
LEIGOD_CHECKSUM_FILE=$CHECKSUM_FILE \
    sh "$REPO_DIR/scripts/fetch-assets.sh" "$DEST_DIR"

cmp "$SOURCE_DIR/acc-gw.router.amd64" "$DEST_DIR/acc-gw.router.amd64"
cmp "$SOURCE_DIR/acc-gw.router.amd64" "$DEST_DIR/acc_upgrade_monitor"
cmp "$SOURCE_DIR/config/ipdatacloud_country.xdb" "$DEST_DIR/config/ipdatacloud_country.xdb"
[ -x "$DEST_DIR/acc-gw.router.amd64" ]
[ -x "$DEST_DIR/acc_upgrade_monitor" ]

printf 'known-good installed binary\n' > "$DEST_DIR/acc-gw.router.amd64"
printf 'tampered fixture\n' > "$SOURCE_DIR/acc-gw.router.amd64"

if LEIGOD_ASSET_SOURCE_DIR=$SOURCE_DIR \
    LEIGOD_CHECKSUM_FILE=$CHECKSUM_FILE \
    sh "$REPO_DIR/scripts/fetch-assets.sh" "$DEST_DIR" >/dev/null 2>&1; then
    echo "expected checksum mismatch to fail" >&2
    exit 1
fi

expected='known-good installed binary'
actual=$(sed -n '1p' "$DEST_DIR/acc-gw.router.amd64")
[ "$actual" = "$expected" ] || {
    echo "destination changed after failed verification" >&2
    exit 1
}

echo "fetch-assets tests passed"
