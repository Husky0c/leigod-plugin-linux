#!/bin/sh
set -eu

umask 077

STATE_DIR=${LEIGOD_STATE_DIR:-/var/lib/leigod}
MAC_FILE=${LEIGOD_DEVICE_MAC_FILE:-$STATE_DIR/device-mac}
MACHINE_ID_FILE=${LEIGOD_MACHINE_ID_FILE:-/etc/machine-id}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

valid_mac() {
    printf '%s\n' "$1" | grep -Eq '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$'
}

hash_seed() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        die "sha256sum or shasum is required"
    fi
}

generate_mac() {
    [ -s "$MACHINE_ID_FILE" ] || die "Machine ID is missing: $MACHINE_ID_FILE"
    machine_id=$(tr -d ' \t\r\n' < "$MACHINE_ID_FILE")
    [ -n "$machine_id" ] || die "Machine ID is empty: $MACHINE_ID_FILE"
    suffix=$(printf 'leigod-device:%s\n' "$machine_id" | hash_seed | cut -c1-10)
    printf '02:%s:%s:%s:%s:%s\n' \
        "$(printf '%s' "$suffix" | cut -c1-2)" \
        "$(printf '%s' "$suffix" | cut -c3-4)" \
        "$(printf '%s' "$suffix" | cut -c5-6)" \
        "$(printf '%s' "$suffix" | cut -c7-8)" \
        "$(printf '%s' "$suffix" | cut -c9-10)"
}

mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"

if [ -e "$MAC_FILE" ] && [ ! -f "$MAC_FILE" ]; then
    die "Device MAC path is not a regular file: $MAC_FILE"
fi

if [ -s "$MAC_FILE" ]; then
    device_mac=$(tr 'A-F' 'a-f' < "$MAC_FILE" | tr -d ' \t\r\n')
    valid_mac "$device_mac" || die "Invalid persisted device MAC: $MAC_FILE"
    printf '%s\n' "$device_mac"
    exit 0
fi

device_mac=$(generate_mac)
valid_mac "$device_mac" || die "Failed to generate a valid device MAC"
tmp_file=$(mktemp "$STATE_DIR/.device-mac.XXXXXX") \
    || die "Unable to create device MAC temporary file"
trap 'rm -f "$tmp_file"' 0 HUP INT TERM
printf '%s\n' "$device_mac" > "$tmp_file"
chmod 0600 "$tmp_file"
mv -f "$tmp_file" "$MAC_FILE"
tmp_file=
trap - 0 HUP INT TERM
printf '%s\n' "$device_mac"
