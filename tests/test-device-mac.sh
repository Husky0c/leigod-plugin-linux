#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-mac-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' 0 HUP INT TERM

MACHINE_ID=$TEST_ROOT/machine-id
STATE_DIR=$TEST_ROOT/state
printf '%s\n' 0123456789abcdef0123456789abcdef > "$MACHINE_ID"

get_mac() {
    LEIGOD_STATE_DIR=$STATE_DIR LEIGOD_MACHINE_ID_FILE=$MACHINE_ID \
        sh "$REPO_DIR/scripts/device-mac.sh"
}

first=$(get_mac)
second=$(get_mac)
[ "$first" = "$second" ] || {
    echo "device MAC changed between invocations" >&2
    exit 1
}
printf '%s\n' "$first" | grep -Eq '^02(:[0-9a-f]{2}){5}$'
[ "$(stat -c '%a' "$STATE_DIR")" = 700 ]
[ "$(stat -c '%a' "$STATE_DIR/device-mac")" = 600 ]

rm -f "$STATE_DIR/device-mac"
[ "$(get_mac)" = "$first" ] || {
    echo "machine-id derivation is not deterministic" >&2
    exit 1
}

printf '%s\n' fedcba9876543210fedcba9876543210 > "$MACHINE_ID"
rm -f "$STATE_DIR/device-mac"
[ "$(get_mac)" != "$first" ] || {
    echo "different machine IDs produced the same MAC" >&2
    exit 1
}

printf '%s\n' invalid > "$STATE_DIR/device-mac"
if get_mac >/dev/null 2>&1; then
    echo "invalid persisted MAC was accepted" >&2
    exit 1
fi

printf '%s\n' '02:aa:bb:cc:dd:ee' > "$STATE_DIR/device-mac"
[ "$(get_mac)" = '02:aa:bb:cc:dd:ee' ]
echo "device-mac tests passed"
