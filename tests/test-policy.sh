#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
cd "$REPO_DIR"

grep -q 'CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW' systemd/leigod_plugin.service
grep -q 'NoNewPrivileges=true' systemd/leigod_plugin.service
grep -q 'PrivateTmp=true' systemd/leigod_plugin.service
grep -q 'RuntimeDirectory=leigod' systemd/leigod_plugin.service
grep -q 'StateDirectory=leigod' systemd/leigod_plugin.service
grep -q 'Restart=on-failure' systemd/leigod_plugin.service
grep -q 'MAX_DAEMON_LOG_BYTES=.*52428800' opt/leigod/steamdeck_acc_monitor.sh
grep -q '/var/lib/leigod/device-mac' README.md
grep -q 'Bazzite' README.md
grep -q 'THIRD_PARTY_NOTICES.md' README.md

if grep -RE '^[[:space:]]*iptables[[:space:]].*-F' \
    install.sh uninstall.sh opt scripts debian; then
    echo "unsafe iptables flush command found" >&2
    exit 1
fi

if grep -q '/sys/class/net/${iface}/address' opt/leigod/steamdeck_acc_monitor.sh; then
    echo "monitor still copies a transient physical MAC" >&2
    exit 1
fi

package_version=$(sed -n 's/^PACKAGE_VERSION=//p' release.env)
upstream_version=$(sed -n 's/^UPSTREAM_VERSION=//p' release.env)
grep -q "^Version: $package_version$" debian/control
grep -q "^version=$upstream_version$" opt/leigod/config/acc_version.ini
echo "policy tests passed"
