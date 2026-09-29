#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
UCI_SHIM=$REPO_DIR/opt/leigod/compat/uci

sh -n "$UCI_SHIM"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-uci-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' 0 HUP INT TERM

uci() {
    LEIGOD_CONF_DIR=$TEST_ROOT/config sh "$UCI_SHIM" "$@"
}

# No token yet: the daemon must see an empty/absent value, not a crash.
if uci get accelerator.base.token > /dev/null 2>&1; then
    echo "uci shim reported a token before one was set" >&2
    exit 1
fi

# A token written by the phone App binding must be readable again.
uci set accelerator.base.token=0123456789abcdef
[ "$(uci get accelerator.base.token)" = 0123456789abcdef ] || {
    echo "uci shim did not persist the token" >&2
    exit 1
}

# The legacy ini path must see the same value (the old code path reads it).
grep -q '^token=0123456789abcdef$' "$TEST_ROOT/config/accelerator.ini" || {
    echo "uci shim did not mirror the token into accelerator.ini" >&2
    cat "$TEST_ROOT/config/accelerator.ini" >&2
    exit 1
}

# With only the ini left, the token must still be found (upgrade from an older
# installation that stored it in the ini file).
rm -f "$TEST_ROOT/config/uci/accelerator"
[ "$(uci get accelerator.base.token)" = 0123456789abcdef ] || {
    echo "uci shim lost the token stored in accelerator.ini" >&2
    exit 1
}

# Defaults expected by the daemon: no-op commands succeed, unknown reads fail.
uci commit accelerator
uci reload
uci changes
uci get accelerator.base.missing > /dev/null 2>&1 && {
    echo "uci shim should report a missing option as failure" >&2
    exit 1
}

echo "uci compatibility tests passed"
