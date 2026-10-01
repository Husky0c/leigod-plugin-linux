#!/bin/sh
set -eu

SOURCE_DIR=$1
CONFIG_DIR=$2

install -d -m 0700 "$CONFIG_DIR"
# The closed-source gateway chmods its INI to 0666 at startup. Keep the
# containing directory private so it cannot expose binding credentials.
# Version metadata follows the installed binary. Account and user settings
# survive a reinstall, including bindings made before the UCI shim existed.
install -m 0644 "$SOURCE_DIR/acc_version.ini" "$CONFIG_DIR/"
for config_file in accelerator.ini accelerator new_upgrade_conf.json; do
    if [ ! -e "$CONFIG_DIR/$config_file" ]; then
        install -m 0600 "$SOURCE_DIR/$config_file" "$CONFIG_DIR/"
    fi
done
chmod 0600 "$CONFIG_DIR/accelerator.ini" "$CONFIG_DIR/accelerator"
if [ -d "$CONFIG_DIR/uci" ]; then
    chmod 0700 "$CONFIG_DIR/uci"
    if [ -f "$CONFIG_DIR/uci/accelerator" ]; then
        chmod 0600 "$CONFIG_DIR/uci/accelerator"
    fi
fi
