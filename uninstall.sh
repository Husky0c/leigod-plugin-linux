#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)

if [ -x "$SCRIPT_DIR/opt/leigod/leigod_uninstall.sh" ]; then
    exec "$SCRIPT_DIR/opt/leigod/leigod_uninstall.sh" "$@"
fi

if [ -x /opt/leigod/leigod_uninstall.sh ]; then
    exec /opt/leigod/leigod_uninstall.sh "$@"
fi

echo "[ERROR] leigod_uninstall.sh was not found" >&2
exit 1
