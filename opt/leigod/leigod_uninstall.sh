#!/bin/sh
set -eu

BASE=/opt/leigod
STATE_DIR=/var/lib/leigod
RUNTIME_DIR=/run/leigod
SERVICE_NAME=leigod_plugin.service
SERVICE_FILE=/etc/systemd/system/$SERVICE_NAME

info() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

[ "$(id -u)" -eq 0 ] || {
    echo "[ERROR] Please run as root" >&2
    exit 1
}

remove_managed_dummy() {
    [ -r "$STATE_DIR/device-mac" ] || return 0
    command -v ip >/dev/null 2>&1 || return 0
    ip -d link show wlan0 2>/dev/null | grep -qw dummy || return 0

    expected=$(tr 'A-F' 'a-f' < "$STATE_DIR/device-mac" | tr -d ' \t\r\n')
    actual=$(cat /sys/class/net/wlan0/address 2>/dev/null || true)
    if [ -n "$expected" ] && [ "$actual" = "$expected" ]; then
        ip link delete wlan0 2>/dev/null || warn "Unable to remove managed dummy wlan0"
    fi
}

stop_remaining_processes() {
    command -v pgrep >/dev/null 2>&1 || return 0
    for pattern in \
        '/opt/leigod/acc-gw\.router\.amd64' \
        '/opt/leigod/acc_upgrade_monitor' \
        '/opt/leigod/steamdeck_acc_monitor\.sh'; do
        for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do
            case "$pid" in
                ''|*[!0-9]*) continue ;;
            esac
            [ "$pid" = "$$" ] || kill "$pid" 2>/dev/null || true
        done
    done
}

info "Stopping Leigod service..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || warn "Service stop returned an error"
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
stop_remaining_processes
remove_managed_dummy

rm -f "$SERVICE_FILE"
systemctl daemon-reload 2>/dev/null || true
rm -rf "$BASE" "$RUNTIME_DIR"

if [ -L /home/leigod ] && [ "$(readlink /home/leigod)" = "$BASE" ]; then
    rm -f /home/leigod
fi

if [ "${LEIGOD_PURGE_STATE:-0}" = 1 ]; then
    rm -rf "$STATE_DIR"
    info "Persistent device identity removed."
else
    info "Preserved $STATE_DIR/device-mac for stable identity after reinstall."
fi

warn "Host firewall tables were intentionally left untouched."
warn "If networking remains altered, reboot instead of flushing the mangle table."
info "Leigod Plugin uninstalled."
