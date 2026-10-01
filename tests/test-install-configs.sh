#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-install-configs-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' 0 HUP INT TERM

CONFIG_DIR=$TEST_ROOT/config
sh "$REPO_DIR/scripts/install-configs.sh" "$REPO_DIR/opt/leigod/config" "$CONFIG_DIR"
cmp "$REPO_DIR/opt/leigod/config/accelerator.ini" "$CONFIG_DIR/accelerator.ini"

# A legacy binding and custom settings must survive a source/TAR reinstall.
printf '\ntoken=fixture-legacy-binding\n' >> "$CONFIG_DIR/accelerator.ini"
printf 'fixture-legacy-config\n' > "$CONFIG_DIR/accelerator"
printf '{"fixture":"user-settings"}\n' > "$CONFIG_DIR/new_upgrade_conf.json"
printf '[info]\nversion=old\n' > "$CONFIG_DIR/acc_version.ini"
mkdir "$CONFIG_DIR/uci"
printf "config base\n\toption token 'fixture-uci-binding'\n" > "$CONFIG_DIR/uci/accelerator"
cp -R "$CONFIG_DIR" "$TEST_ROOT/before"
chmod 0644 "$CONFIG_DIR/accelerator.ini" "$CONFIG_DIR/uci/accelerator"

sh "$REPO_DIR/scripts/install-configs.sh" "$REPO_DIR/opt/leigod/config" "$CONFIG_DIR"
for config_file in accelerator.ini accelerator new_upgrade_conf.json uci/accelerator; do
    cmp "$TEST_ROOT/before/$config_file" "$CONFIG_DIR/$config_file"
done
cmp "$REPO_DIR/opt/leigod/config/acc_version.ini" "$CONFIG_DIR/acc_version.ini"
[ "$(stat -c %a "$CONFIG_DIR/accelerator.ini")" = 600 ]
[ "$(stat -c %a "$CONFIG_DIR/accelerator")" = 600 ]
[ "$(stat -c %a "$CONFIG_DIR/uci/accelerator")" = 600 ]
[ "$(stat -c %a "$CONFIG_DIR/uci")" = 700 ]
[ "$(stat -c %a "$CONFIG_DIR")" = 700 ]
echo "install configuration persistence tests passed"
