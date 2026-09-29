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
    { if ($3 !~ /^[0-9]+$/) { print "non-numeric VSZ column: " $0; exit 1 } }
    END { exit 0 }
' || exit 1

# The query the upstream gateway runs is `ps ax | grep acc-gw.router.amd64`.
# Its own shell/grep processes are matched by that grep, and the BusyBox parser
# then treats them as gateway processes, so the shim must hide them.
sh -c 'exec -a "sh -c ps ax | grep acc-gw.router.amd64" sleep 30' &
fake_query_pid=$!
trap 'kill "$helper_pid" "$fake_query_pid" 2>/dev/null || true' 0 HUP INT TERM

sleep 1
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
[ "$(sh "$PS_SHIM" -eo pid= -p "$$")" = "$("$real_ps" -eo pid= -p "$$")" ] || {
    echo "ps shim mangled a custom-format invocation" >&2
    exit 1
}

echo "ps compatibility tests passed"
