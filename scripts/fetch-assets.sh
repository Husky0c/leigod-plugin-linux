#!/bin/sh
set -eu

umask 077

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 DESTINATION_ROOT" >&2
    exit 2
fi

DEST_ROOT=$1
SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/.." && pwd)
CHECKSUM_FILE=${LEIGOD_CHECKSUM_FILE:-$REPO_DIR/checksums.sha256}
BASE_URL=${LEIGOD_BASE_URL:-http://119.3.40.126}
ASSET_SOURCE_DIR=${LEIGOD_ASSET_SOURCE_DIR:-}
WORK_DIR=
ACC_STAGE=
UPGRADE_STAGE=
XDB_STAGE=

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

cleanup() {
    [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"
    [ -z "$ACC_STAGE" ] || rm -f "$ACC_STAGE"
    [ -z "$UPGRADE_STAGE" ] || rm -f "$UPGRADE_STAGE"
    [ -z "$XDB_STAGE" ] || rm -f "$XDB_STAGE"
}

trap cleanup 0
trap 'exit 1' HUP INT TERM

[ -r "$CHECKSUM_FILE" ] || die "Checksum file is missing or unreadable: $CHECKSUM_FILE"

if [ -z "$ASSET_SOURCE_DIR" ]; then
    command -v curl >/dev/null 2>&1 || die "curl is required"
    case "$BASE_URL" in
        http://*|https://*) ;;
        *) die "LEIGOD_BASE_URL must use http:// or https://" ;;
    esac
fi

if command -v sha256sum >/dev/null 2>&1; then
    sha256_file() {
        sha256sum "$1" | awk '{print $1}'
    }
elif command -v shasum >/dev/null 2>&1; then
    sha256_file() {
        shasum -a 256 "$1" | awk '{print $1}'
    }
else
    die "sha256sum or shasum is required"
fi

expected_hash() {
    asset_name=$1
    expected=$(awk -v name="$asset_name" '$2 == name { print $1; exit }' "$CHECKSUM_FILE")
    [ "${#expected}" -eq 64 ] || die "No valid SHA-256 entry for $asset_name"
    case "$expected" in
        *[!0-9A-Fa-f]*) die "Invalid SHA-256 entry for $asset_name" ;;
    esac
    printf '%s\n' "$expected" | tr 'A-F' 'a-f'
}

fetch_and_verify() {
    asset_name=$1
    source_relative_path=$2
    output_path=$3

    if [ -n "$ASSET_SOURCE_DIR" ]; then
        source_path=$ASSET_SOURCE_DIR/$source_relative_path
        [ -f "$source_path" ] || die "Bundled asset is missing: $source_path"
        echo "[INFO] Verifying bundled $asset_name..."
        cp "$source_path" "$output_path"
    else
        echo "[INFO] Downloading $asset_name..."
        curl --fail --location --show-error --silent \
            --proto '=http,https' --proto-redir '=http,https' \
            --connect-timeout 15 --max-time 300 \
            --retry 3 --retry-delay 2 \
            -o "$output_path" "$BASE_URL/$asset_name" \
            || die "Failed to download $asset_name"
    fi

    expected=$(expected_hash "$asset_name")
    actual=$(sha256_file "$output_path" | tr 'A-F' 'a-f')
    if [ "$actual" != "$expected" ]; then
        rm -f "$output_path"
        die "SHA-256 mismatch for $asset_name (expected $expected, got $actual)"
    fi
    echo "[INFO] SHA-256 verified: $asset_name"
}

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/leigod-assets.XXXXXX") \
    || die "Failed to create temporary download directory"

fetch_and_verify "acc-gw.router.amd64" "acc-gw.router.amd64" "$WORK_DIR/acc-gw.router.amd64"
fetch_and_verify "ipdatacloud_country.xdb" "config/ipdatacloud_country.xdb" "$WORK_DIR/ipdatacloud_country.xdb"

mkdir -p "$DEST_ROOT/config"
ACC_STAGE=$(mktemp "$DEST_ROOT/.acc-gw.router.amd64.XXXXXX") \
    || die "Failed to create gateway staging file"
UPGRADE_STAGE=$(mktemp "$DEST_ROOT/.acc_upgrade_monitor.XXXXXX") \
    || die "Failed to create updater staging file"
XDB_STAGE=$(mktemp "$DEST_ROOT/config/.ipdatacloud_country.xdb.XXXXXX") \
    || die "Failed to create database staging file"

cp "$WORK_DIR/acc-gw.router.amd64" "$ACC_STAGE"
chmod 0755 "$ACC_STAGE"
cp "$WORK_DIR/acc-gw.router.amd64" "$UPGRADE_STAGE"
chmod 0755 "$UPGRADE_STAGE"
cp "$WORK_DIR/ipdatacloud_country.xdb" "$XDB_STAGE"
chmod 0644 "$XDB_STAGE"

# Rename only after every asset has downloaded and verified. Each replacement
# is atomic within its destination filesystem, including over running binaries.
mv -f "$ACC_STAGE" "$DEST_ROOT/acc-gw.router.amd64"
ACC_STAGE=
mv -f "$UPGRADE_STAGE" "$DEST_ROOT/acc_upgrade_monitor"
UPGRADE_STAGE=
mv -f "$XDB_STAGE" "$DEST_ROOT/config/ipdatacloud_country.xdb"
XDB_STAGE=

echo "[INFO] Verified Leigod assets installed in $DEST_ROOT"
