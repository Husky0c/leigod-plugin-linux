#!/bin/sh
set -u

umask 077

BASE_PATH=${LEIGOD_BASE_PATH:-/opt/leigod}
RUNTIME_DIR=${LEIGOD_RUNTIME_DIR:-/run/leigod}
LOCK_DIR=$RUNTIME_DIR/monitor.lock
ACC_TMP_DIR=${LEIGOD_ACC_TMP_DIR:-/tmp/acc}
UPGRADE_FLAG=$ACC_TMP_DIR/upgrade_flag
MAX_START_FAILURES=${LEIGOD_MAX_START_FAILURES:-3}
MAX_DAEMON_LOG_BYTES=${LEIGOD_MAX_DAEMON_LOG_BYTES:-52428800}
MAX_WEB_CRASHES=${LEIGOD_MAX_WEB_CRASHES:-3}
WEB_CRASH_WINDOW=${LEIGOD_WEB_CRASH_WINDOW:-900}
MAX_WEB_RECOVERIES=${LEIGOD_MAX_WEB_RECOVERIES:-5}
run_env=${1:-}

# Upstream build 1.3.0.01 locates its own helper processes with
# "ps ax | grep acc-gw.router.amd64" and parses the result as BusyBox output.
# The util-linux "ps ax" layout makes that parse throw an uncaught
# std::invalid_argument (SIGABRT / "dumped core"), or makes the daemon respawn
# its "-r web" helper every 5 seconds. Prefer the compatibility shim shipped in
# $BASE_PATH/compat over the system ps for the whole service process tree.
PATH=$BASE_PATH/compat:$PATH
export PATH

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

matching_pids() {
    process_name=$1
    pattern=$2
    pids=$(pgrep -f "$process_name" 2>/dev/null || true)
    [ -n "$pids" ] || return 0

    for pid in $pids; do
        case "$pid" in
            ''|*[!0-9]*) continue ;;
        esac
        if [ -r "/proc/$pid/cmdline" ]; then
            cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline")
            case "$cmdline" in
                *"$pattern"*) printf '%s\n' "$pid" ;;
            esac
        fi
    done
}

first_matching_pid() {
    for pid in $(matching_pids "$1" "$2"); do
        printf '%s\n' "$pid"
        return 0
    done
    return 0
}

is_process_running() {
    [ -n "$(first_matching_pid "$1" "$2")" ]
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
case "$MAX_WEB_CRASHES" in
    ''|*[!0-9]*|0) MAX_WEB_CRASHES=3 ;;
esac
case "$WEB_CRASH_WINDOW" in
    ''|*[!0-9]*|0) WEB_CRASH_WINDOW=900 ;;
esac
case "$MAX_WEB_RECOVERIES" in
    ''|*[!0-9]*|0) MAX_WEB_RECOVERIES=5 ;;
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

log_acc_log_tails() {
    command -v tail >/dev/null 2>&1 || return 0
    for log_file in "$ACC_TMP_DIR/log/web_api.log" "$ACC_TMP_DIR/log/acc_daemon.log"; do
        [ -r "$log_file" ] || continue
        log_message "Last lines of $log_file:"
        tail -n 10 "$log_file" 2>/dev/null | while IFS= read -r line; do
            case $(printf '%s' "$line" | tr '[:upper:]' '[:lower:]') in
                *token*|*password*|*authorization*|*secret*)
                    log_message "  [credential-related log line redacted]"
                    ;;
                *) log_message "  $line" ;;
            esac
        done
    done
}

stop_accelerator_processes() {
    stop_pids=$(matching_pids "acc-gw.router.$arch" "-r")
    [ -n "$stop_pids" ] || return 0

    for pid in $stop_pids; do
        kill "$pid" 2>/dev/null || true
    done

    stop_wait=0
    while [ "$stop_wait" -lt 10 ]; do
        if [ -z "$(matching_pids "acc-gw.router.$arch" "-r")" ]; then
            return 0
        fi
        stop_wait=$((stop_wait + 1))
        sleep 1
    done

    log_message "WARNING: accelerator processes ignored SIGTERM; sending SIGKILL"
    for pid in $(matching_pids "acc-gw.router.$arch" "-r"); do
        kill -9 "$pid" 2>/dev/null || true
    done
    sleep 1
    return 0
}

recycle_accelerator_daemon() {
    web_recoveries=$((web_recoveries + 1))
    log_message "Web helper restarted $web_recent_crashes times within ${WEB_CRASH_WINDOW}s; recycling the accelerator daemon (recovery $web_recoveries/$MAX_WEB_RECOVERIES)"
    log_acc_log_tails
    stop_accelerator_processes

    web_crash_times=
    web_recent_crashes=0
    last_web_pid=

    if [ "$web_recoveries" -gt "$MAX_WEB_RECOVERIES" ]; then
        log_message "Web helper keeps crash-looping after $MAX_WEB_RECOVERIES recoveries; giving up so systemd can report and rate-limit the failure"
        exit 1
    fi
    sleep 2
    return 0
}

prune_web_crashes() {
    now_seconds=$(date +%s)
    web_recent_crashes=0
    kept_web_crashes=
    for crash_stamp in $web_crash_times; do
        if [ "$((now_seconds - crash_stamp))" -le "$WEB_CRASH_WINDOW" ]; then
            kept_web_crashes="$kept_web_crashes $crash_stamp"
            web_recent_crashes=$((web_recent_crashes + 1))
        fi
    done
    web_crash_times=$kept_web_crashes
}

# The closed-source daemon forks a "-r web" helper that serves the phone App.
# Upstream aborts that helper on internal errors (issue #5), and the daemon
# immediately forks a replacement while the dying helper still owns its port,
# which turns a single failure into a crash loop. The monitor only used to
# watch the "-r daemon" process, so the loop stayed invisible in systemd apart
# from the resulting core dumps. Track the helper PID and recycle the whole
# accelerator process group when it keeps churning.
track_web_helper() {
    web_helper_pid=$(first_matching_pid "acc-gw.router.$arch" "-r web")
    [ -n "$web_helper_pid" ] || return 0

    if [ -z "$last_web_pid" ]; then
        last_web_pid=$web_helper_pid
        return 0
    fi

    if [ "$web_helper_pid" = "$last_web_pid" ]; then
        prune_web_crashes
        if [ "$web_recent_crashes" -eq 0 ]; then
            # The helper has been stable for a full window, so the recovery
            # budget applies to consecutive failure periods only.
            web_recoveries=0
        fi
        return 0
    fi

    last_web_pid=$web_helper_pid
    log_message "Web helper was replaced (new PID $web_helper_pid)"
    web_crash_times="$web_crash_times $(date +%s)"
    prune_web_crashes
    if [ "$web_recent_crashes" -ge "$MAX_WEB_CRASHES" ]; then
        recycle_accelerator_daemon
    fi
    return 0
}

# Report whether a binding token reached the device, without printing its value.
# The upstream build stores the token through uci (mirrored into accelerator.ini
# by compat/uci), so this tells the user from the journal whether the phone App
# managed to bind this host.
log_binding_state() {
    token_files=
    for candidate in \
        "$BASE_PATH/config/accelerator.ini" \
        "$BASE_PATH/config/accelerator" \
        "$BASE_PATH/config/uci/accelerator"; do
        [ -r "$candidate" ] || continue
        if grep -Eq '^[[:space:]]*(option[[:space:]]+token[[:space:]]+[^[:space:]]|token[[:space:]]*=[[:space:]]*[^[:space:]])' "$candidate"; then
            token_files="$token_files $candidate"
        fi
    done

    if [ -n "$token_files" ]; then
        log_message "Binding token present in:$token_files"
    else
        log_message "No binding token stored yet; bind this device from the phone App"
    fi
}

failures=0
updater_notice_written=0
last_web_pid=
web_crash_times=
web_recent_crashes=0
web_recoveries=0
log_message "Monitor started with PID $$"
log_message "Persistent device MAC: $DEVICE_MAC"
log_binding_state

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
            last_web_pid=
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

    track_web_helper

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
