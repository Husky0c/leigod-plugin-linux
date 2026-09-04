#!/bin/sh
set -u

umask 077

BASE_PATH=/opt/leigod
RUNTIME_DIR=${LEIGOD_RUNTIME_DIR:-/run/leigod}
LOCK_DIR=$RUNTIME_DIR/monitor.lock
ACC_TMP_DIR=${LEIGOD_ACC_TMP_DIR:-/tmp/acc}
UPGRADE_FLAG=$ACC_TMP_DIR/upgrade_flag
MAX_START_FAILURES=${LEIGOD_MAX_START_FAILURES:-3}
MAX_DAEMON_LOG_BYTES=${LEIGOD_MAX_DAEMON_LOG_BYTES:-52428800}
run_env=${1:-}

log_message() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cleanup() {
    if [ -r "$LOCK_DIR/pid" ] && [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
        rm -rf "$LOCK_DIR"
    fi
}

trap cleanup 0
trap 'exit 0' HUP INT TERM

case $(uname -m) in
    x86_64) arch=amd64 ;;
    *)
        log_message "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

mkdir -p "$RUNTIME_DIR"
chmod 0700 "$RUNTIME_DIR"
mkdir -p "$ACC_TMP_DIR/log"
chmod 0700 "$ACC_TMP_DIR" "$ACC_TMP_DIR/log"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    old_pid=
    [ ! -r "$LOCK_DIR/pid" ] || old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    case "$old_pid" in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$old_pid" 2>/dev/null; then
                log_message "Monitor is already running with PID $old_pid"
                exit 1
            fi
            ;;
    esac
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || {
        log_message "Unable to acquire monitor lock"
        exit 1
    }
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"

DEVICE_MAC=$(LEIGOD_STATE_DIR=${LEIGOD_STATE_DIR:-/var/lib/leigod} \
    "$BASE_PATH/device-mac.sh") || exit 1

setup_wlan0() {
    if ! ip link show wlan0 >/dev/null 2>&1; then
        ip link add wlan0 type dummy || {
            log_message "Unable to create dummy wlan0; check dummy kernel support and CAP_NET_ADMIN"
            return 1
        }
    elif ! ip -d link show wlan0 2>/dev/null | grep -qw dummy; then
        log_message "Existing wlan0 is a physical interface; its MAC is managed externally"
        log_message "Disable NetworkManager MAC randomization before binding (see README)"
        return 0
    fi

    current_mac=$(cat /sys/class/net/wlan0/address 2>/dev/null || true)
    if [ "$current_mac" != "$DEVICE_MAC" ]; then
        ip link set wlan0 down || return 1
        ip link set wlan0 address "$DEVICE_MAC" || return 1
    fi
    ip link set wlan0 up || return 1
    log_message "Stable dummy wlan0 ready with MAC $DEVICE_MAC"
}

setup_wlan0 || exit 1

is_process_running() {
    process_name=$1
    pattern=$2
    pids=$(pgrep -f "$process_name" 2>/dev/null || true)
    [ -n "$pids" ] || return 1

    for pid in $pids; do
        case "$pid" in
            ''|*[!0-9]*) continue ;;
        esac
        if [ -r "/proc/$pid/cmdline" ]; then
            cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline")
            case "$cmdline" in
                *"$pattern"*) return 0 ;;
            esac
        fi
    done
    return 1
}

start_main_daemon() {
    if [ "$run_env" = "test" ]; then
        "$BASE_PATH/acc-gw.router.$arch" -d debug -r daemon -m tun -p 5588 \
            >/dev/null 2>&1 </dev/null &
    else
        "$BASE_PATH/acc-gw.router.$arch" -r daemon -m tun -p 5588 \
            >/dev/null 2>&1 </dev/null &
    fi
    sleep 2
    is_process_running "acc-gw.router.$arch" "-r daemon"
}

start_updater() {
    if [ "$run_env" = "test" ]; then
        "$BASE_PATH/acc_upgrade_monitor" -d debug -r upgrade \
            >/dev/null 2>&1 </dev/null &
    else
        "$BASE_PATH/acc_upgrade_monitor" -r upgrade \
            >/dev/null 2>&1 </dev/null &
    fi
}

case "$MAX_START_FAILURES" in
    ''|*[!0-9]*|0) MAX_START_FAILURES=3 ;;
esac
case "$MAX_DAEMON_LOG_BYTES" in
    ''|*[!0-9]*|0) MAX_DAEMON_LOG_BYTES=52428800 ;;
esac

truncate_oversized_daemon_log() {
    daemon_log=$ACC_TMP_DIR/log/acc_daemon.log
    [ -f "$daemon_log" ] || return 0
    log_size=$(wc -c < "$daemon_log" 2>/dev/null || echo 0)
    case "$log_size" in
        ''|*[!0-9]*) return 0 ;;
    esac
    if [ "$log_size" -gt "$MAX_DAEMON_LOG_BYTES" ]; then
        : > "$daemon_log"
        log_message "Truncated daemon log after it exceeded $MAX_DAEMON_LOG_BYTES bytes"
    fi
}

failures=0
updater_notice_written=0
log_message "Monitor started with PID $$"
log_message "Persistent device MAC: $DEVICE_MAC"

while :; do
    if [ -f "$UPGRADE_FLAG" ]; then
        log_message "Upgrade flag detected; exiting cleanly"
        exit 0
    fi

    if is_process_running "acc-gw.router.$arch" "-r daemon"; then
        failures=0
    else
        log_message "Main daemon is not running; starting it"
        if start_main_daemon; then
            failures=0
            log_message "Main daemon started successfully"
        else
            failures=$((failures + 1))
            log_message "Main daemon start failed ($failures/$MAX_START_FAILURES)"
            if [ "$failures" -ge "$MAX_START_FAILURES" ]; then
                log_message "Giving up so systemd can report and rate-limit the failure"
                exit 1
            fi
        fi
    fi

    if [ "${LEIGOD_ENABLE_UPDATER:-0}" = "1" ]; then
        if ! is_process_running acc_upgrade_monitor "-r upgrade"; then
            log_message "WARNING: starting unverified upstream updater"
            start_updater
        fi
    elif [ "$updater_notice_written" -eq 0 ]; then
        log_message "Automatic updater disabled; use the verified installer"
        updater_notice_written=1
    fi

    truncate_oversized_daemon_log
    sleep 5
done
