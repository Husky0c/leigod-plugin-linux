#!/bin/sh
set -eu

BASE="/opt/leigod"
SERVICE_NAME="leigod_plugin.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run as root" >&2
    exit 1
fi

info "Stopping Leigod service..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "$SERVICE_FILE"
systemctl daemon-reload 2>/dev/null || true

# Kill only exact Leigod process names if the service did not stop them.
if command -v pidof >/dev/null 2>&1; then
    for process_name in acc-gw.router.amd64 acc_upgrade_monitor steamdeck_acc_monitor.sh; do
        for pid in $(pidof "$process_name" 2>/dev/null || true); do
            case "$pid" in
                ''|*[!0-9]*) continue ;;
            esac
            kill "$pid" 2>/dev/null || true
        done
    done
fi

rm -rf "$BASE" /tmp/acc
rm -f /var/run/acc_daemon.lock

if [ -L /home/leigod ] && [ "$(readlink /home/leigod)" = "$BASE" ]; then
    rm -f /home/leigod
fi

# Never flush a shared host firewall table. The old upstream-derived script
# used `iptables -t mangle -F`, which could delete unrelated Docker, VPN, and
# firewall rules. The service is stopped gracefully so the Leigod process can
# remove its own transient rules. A reboot is the safe fallback for stale rules.
warn "Host firewall tables were intentionally left untouched."
warn "If networking remains altered, reboot instead of flushing the mangle table."
info "Leigod Plugin uninstalled."
