#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
PS_SHIM=$REPO_DIR/opt/leigod/compat/ps

sh -n "$PS_SHIM"

# A normal process must stay listed, with a numeric third column (the upstream
# gateway calls std::stoi() on that column).
sleep 30 &
helper_pid=$!
trap 'kill "$helper_pid" 2>/dev/null || true' 0 HUP INT TERM

shim_output=$(sh "$PS_SHIM" ax)
printf '%s\n' "$shim_output" | grep -q "sleep 30" || {
    echo "ps shim dropped a regular process" >&2
    exit 1
}

printf '%s\n' "$shim_output" | awk '
    { if ($3 !~ /^[0-9]+$/) { print "non-numeric VSZ column: " $0; failed = 1 } }
    END { exit failed }
' || exit 1

# The query the upstream gateway runs is `ps ax | grep acc-gw.router.amd64`.
# Its own shell/grep processes are matched by that grep, and the BusyBox parser
# then treats them as gateway processes, so the shim must hide them.
bash -c 'exec -a "sh -c ps ax | grep acc-gw.router.amd64" sleep 30' &
fake_query_pid=$!
trap 'kill "$helper_pid" "$fake_query_pid" 2>/dev/null || true' 0 HUP INT TERM

sleep 1
kill -0 "$fake_query_pid" || {
    echo "query fixture failed to start" >&2
    exit 1
}
if sh "$PS_SHIM" ax | grep -q 'ps ax | grep acc-gw.router.amd64'; then
    echo "ps shim still exposes the query helper process" >&2
    exit 1
fi

# Anything that is not an "all processes" listing is passed through untouched.
real_ps=
for candidate in /usr/bin/ps /bin/ps /usr/local/bin/ps; do
    if [ -x "$candidate" ]; then
        real_ps=$candidate
        break
    fi
done
[ "$(sh "$PS_SHIM" -o pid= -p "$$")" = "$("$real_ps" -o pid= -p "$$")" ] || {
    echo "ps shim mangled a custom-format invocation" >&2
    exit 1
}

# An amd64 executable appears twice in Rosetta's cmdline. The translated
# gateway command must have one executable, while native hosts stay intact.
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/leigod-ps-test.XXXXXX")
cp "$(command -v dash)" "$TEST_ROOT/acc-gw.router.amd64"
"$TEST_ROOT/acc-gw.router.amd64" -c 'sleep 30; :' &
gateway_pid=$!
trap 'pkill -P "$gateway_pid" 2>/dev/null || true; kill "$helper_pid" "$fake_query_pid" "$gateway_pid" 2>/dev/null || true; rm -rf "$TEST_ROOT"' 0 HUP INT TERM
sleep 1
kill -0 "$gateway_pid"
sh "$PS_SHIM" ax | awk -v pid="$gateway_pid" -v executable="$TEST_ROOT/acc-gw.router.amd64" '
    $1 == pid {
        found = 1
        if ($5 != executable || $6 != "-c") failed = 1
    }
    END { exit (!found || failed) }
' || {
    echo "ps shim failed to normalize the gateway executable" >&2
    exit 1
}

echo "ps compatibility tests passed"
