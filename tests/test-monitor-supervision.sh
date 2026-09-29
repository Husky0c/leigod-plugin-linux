#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
MONITOR=$REPO_DIR/opt/leigod/steamdeck_acc_monitor.sh

sh -n "$MONITOR"
grep -q 'LEIGOD_BASE_PATH' "$MONITOR"
grep -q 'LEIGOD_MAX_WEB_CRASHES' "$MONITOR"
grep -q 'LEIGOD_WEB_CRASH_WINDOW' "$MONITOR"
grep -q 'LEIGOD_MAX_WEB_RECOVERIES' "$MONITOR"

if ! unshare --user --map-root-user --net true 2>/dev/null; then
    echo "monitor supervision test skipped: unprivileged user/network namespaces are unavailable"
    exit 0
fi

# The test must not see (or disturb) a real leigod installation, so it runs in
# a private PID namespace with a freshly mounted /proc.
if ! unshare --user --map-root-user --net --pid --fork --mount \
    sh -c 'mount -t proc proc /proc' 2>/dev/null; then
    echo "monitor supervision test skipped: cannot isolate a private PID namespace"
    exit 0
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-monitor-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' 0 HUP INT TERM

BASE=$TEST_ROOT/base
mkdir -p "$BASE/config"

# Stand-in for the closed-source gateway: the "-r daemon" process keeps forking
# short-lived "-r web" helpers, which is the upstream crash loop reported in
# issue #5 (the helper aborts, the daemon forks a replacement, repeat).
cat > "$BASE/acc-gw.router.amd64" <<'STUB'
#!/bin/sh
case " $* " in
    *" -r daemon "*)
        log_dir=${LEIGOD_ACC_TMP_DIR:-/tmp/acc}/log
        mkdir -p "$log_dir"
        printf '%s\n' 'child process recv signal, will exit, pid:1, sig:6, signame:Aborted' >> "$log_dir/acc_daemon.log"
        while :; do
            sh "$0" -r web -m tun -p 5588 >/dev/null 2>&1 &
            sleep 1
        done
        ;;
    *)
        sleep 1
        ;;
esac
STUB
chmod 0755 "$BASE/acc-gw.router.amd64"
cp "$REPO_DIR/scripts/device-mac.sh" "$BASE/device-mac.sh"
chmod 0755 "$BASE/device-mac.sh"

run_monitor() {
    LEIGOD_BASE_PATH=$BASE \
    LEIGOD_RUNTIME_DIR=$TEST_ROOT/run \
    LEIGOD_ACC_TMP_DIR=$TEST_ROOT/acc \
    LEIGOD_STATE_DIR=$TEST_ROOT/state \
    LEIGOD_MAX_WEB_CRASHES=2 \
    LEIGOD_MAX_WEB_RECOVERIES=1 \
        timeout 120 unshare --user --map-root-user --net --pid --fork --mount \
            sh -c 'mount -t proc proc /proc && exec sh "$1"' sh "$MONITOR"
}

monitor_log=$TEST_ROOT/monitor.log
monitor_status=0
if run_monitor > "$monitor_log" 2>&1; then
    monitor_status=0
else
    monitor_status=$?
fi

check_log() {
    grep -q "$1" "$monitor_log" || {
        echo "expected monitor log to contain: $1" >&2
        cat "$monitor_log" >&2
        exit 1
    }
}

check_log 'Stable dummy wlan0 ready'
check_log 'Web helper was replaced'
check_log 'recycling the accelerator daemon (recovery 1/1)'
check_log 'child process recv signal, will exit'
check_log 'giving up so systemd can report and rate-limit the failure'

daemon_starts=$(grep -c 'Main daemon started successfully' "$monitor_log" || true)
[ "$daemon_starts" -ge 2 ] || {
    echo "expected the monitor to restart the daemon after recycling it, saw $daemon_starts starts" >&2
    cat "$monitor_log" >&2
    exit 1
}

[ "$monitor_status" -eq 1 ] || {
    echo "expected the monitor to exit 1 after the recovery budget was exhausted, got $monitor_status" >&2
    cat "$monitor_log" >&2
    exit 1
}

! pgrep -f 'leigod-monitor-test.*acc-gw\.router\.amd64' >/dev/null 2>&1 || {
    echo "monitor left accelerator processes behind" >&2
    exit 1
}

echo "monitor supervision tests passed"
