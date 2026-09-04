#!/bin/sh
set -eu

umask 022

BASE=/opt/leigod
SERVICE_NAME=leigod_plugin.service
SERVICE_FILE=/etc/systemd/system/$SERVICE_NAME
SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
SERVICE_WAS_ACTIVE=0
INSTALL_COMPLETE=0

[ -r "$SCRIPT_DIR/release.env" ] || {
    echo "[ERROR] Missing release.env" >&2
    exit 1
}
# shellcheck disable=SC1091
. "$SCRIPT_DIR/release.env"
VERSION=$PACKAGE_VERSION

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    printf '%b[INFO]%b %s\n' "$GREEN" "$NC" "$*"
}

warn() {
    printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*" >&2
}

error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2
    exit 1
}

restore_previous_service() {
    status=$?
    trap - 0
    if [ "$status" -ne 0 ] && [ "$INSTALL_COMPLETE" -eq 0 ] \
        && [ "$SERVICE_WAS_ACTIVE" -eq 1 ]; then
        warn "Installation failed; attempting to restart the previously active service"
        systemctl restart "$SERVICE_NAME" 2>/dev/null || \
            warn "Previous service could not be restarted; inspect it with systemctl status"
    fi
    exit "$status"
}

trap restore_previous_service 0
trap 'exit 1' HUP INT TERM

[ "$(id -u)" -eq 0 ] || error "Please run as root (sudo ./install.sh)"
[ "$(uname -m)" = x86_64 ] || error "Only x86_64 is supported; current: $(uname -m)"
command -v systemctl >/dev/null 2>&1 || error "systemctl is required"
[ -d /run/systemd/system ] || error "A running systemd system instance is required"

detect_platform() {
    ID=
    ID_LIKE=
    VARIANT_ID=
    IMAGE_ID=
    [ ! -r /etc/os-release ] || . /etc/os-release

    platform_words="$ID $ID_LIKE $VARIANT_ID $IMAGE_ID"
    case "$platform_words" in
        *bazzite*|*silverblue*|*kinoite*|*sericea*|*coreos*|*bootc*)
            error "Atomic/immutable distributions are not supported by this host installer: $platform_words"
            ;;
    esac

    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER=apt
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER=dnf
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER=pacman
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER=zypper
    else
        error "Supported package managers: apt-get, dnf, pacman, zypper"
    fi
    info "Detected package manager: $PKG_MANAGER"
}

install_deps() {
    info "Installing runtime dependencies..."
    case "$PKG_MANAGER" in
        apt)
            apt-get update
            apt-get install -y --no-install-recommends \
                ca-certificates curl iproute2 ipset iptables procps
            ;;
        dnf)
            dnf install -y \
                ca-certificates curl iproute ipset iptables procps-ng
            ;;
        pacman)
            pacman -S --noconfirm --needed \
                ca-certificates curl iproute2 ipset iptables procps-ng
            ;;
        zypper)
            zypper --non-interactive refresh
            zypper --non-interactive install \
                ca-certificates curl iproute2 ipset iptables procps
            ;;
    esac
}

verify_runtime() {
    missing=
    for command_name in curl grep ip ipset iptables pgrep sha256sum systemctl; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing="$missing $command_name"
        fi
    done
    [ -z "$missing" ] || error "Missing required commands:$missing"
    [ -c /dev/net/tun ] || error "/dev/net/tun is unavailable; load the tun module before installing"
}

stop_existing_service() {
    if systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            SERVICE_WAS_ACTIVE=1
        fi
        info "Stopping the existing service before replacing files..."
        systemctl stop "$SERVICE_NAME" || error "Failed to stop the existing service"
    fi
}

download_binaries() {
    checksum_file=${LEIGOD_CHECKSUM_FILE:-$SCRIPT_DIR/checksums.sha256}
    asset_source=${LEIGOD_ASSET_SOURCE_DIR:-}

    if [ -z "$asset_source" ] \
        && [ -f "$SCRIPT_DIR/opt/leigod/acc-gw.router.amd64" ] \
        && [ -f "$SCRIPT_DIR/opt/leigod/config/ipdatacloud_country.xdb" ]; then
        asset_source=$SCRIPT_DIR/opt/leigod
    fi

    info "Fetching Leigod assets with pinned SHA-256 verification..."
    LEIGOD_BASE_URL=${LEIGOD_BASE_URL:-http://119.3.40.126} \
    LEIGOD_CHECKSUM_FILE=$checksum_file \
    LEIGOD_ASSET_SOURCE_DIR=$asset_source \
        sh "$SCRIPT_DIR/scripts/fetch-assets.sh" "$BASE" \
        || error "Failed to fetch or verify Leigod assets"
}

install_files() {
    info "Installing files to $BASE..."
    install -d -m 0755 "$BASE/config"
    install -m 0755 "$SCRIPT_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$BASE/"
    install -m 0755 "$SCRIPT_DIR/opt/leigod/leigod_uninstall.sh" "$BASE/"
    install -m 0755 "$SCRIPT_DIR/scripts/device-mac.sh" "$BASE/"
    install -m 0644 "$SCRIPT_DIR/opt/leigod/fake_os-release" "$BASE/"
    install -m 0644 "$SCRIPT_DIR/opt/leigod/fake_product_name" "$BASE/"
    install -m 0644 "$SCRIPT_DIR/opt/leigod/config/acc_version.ini" "$BASE/config/"
    install -m 0644 "$SCRIPT_DIR/opt/leigod/config/accelerator.ini" "$BASE/config/"
    install -m 0644 "$SCRIPT_DIR/opt/leigod/config/new_upgrade_conf.json" "$BASE/config/"
    : > "$BASE/config/accelerator"
    chmod 0644 "$BASE/config/accelerator"
}

create_symlink() {
    if [ -d /home/leigod ] && [ ! -L /home/leigod ]; then
        if rmdir /home/leigod 2>/dev/null; then
            info "Removed empty directory /home/leigod"
        else
            error "/home/leigod is a non-empty directory; move it before installing"
        fi
    fi
    ln -sfn "$BASE" /home/leigod
}

setup_service() {
    info "Installing the hardened systemd service..."
    install -m 0644 "$SCRIPT_DIR/systemd/leigod_plugin.service" "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
}

main_daemon_running() {
    pgrep -f '/opt/leigod/acc-gw\.router\.amd64.*-r daemon' >/dev/null 2>&1
}

start_service() {
    info "Starting Leigod Plugin Service..."
    systemctl restart "$SERVICE_NAME" || error "Failed to start $SERVICE_NAME"

    attempts=0
    while [ "$attempts" -lt 25 ]; do
        if systemctl is-active --quiet "$SERVICE_NAME" && main_daemon_running; then
            info "Service and acceleration daemon are running."
            return 0
        fi
        if systemctl is-failed --quiet "$SERVICE_NAME"; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    journalctl -u "$SERVICE_NAME" -n 40 --no-pager >&2 || true
    error "$SERVICE_NAME did not become healthy; installation is incomplete"
}

print_summary() {
    echo ""
    echo "============================================"
    echo " Leigod Plugin v$VERSION installed!"
    echo "============================================"
    echo " Device MAC: $(cat /var/lib/leigod/device-mac 2>/dev/null || echo pending)"
    echo " Manage: systemctl {status|restart|stop} $SERVICE_NAME"
    echo " Logs:   journalctl -u $SERVICE_NAME"
    echo ""
}

echo ""
echo "Leigod Plugin v$VERSION Installer"
echo "============================================"
echo ""

detect_platform
install_deps
verify_runtime
stop_existing_service
download_binaries
install_files
create_symlink
setup_service
start_service
INSTALL_COMPLETE=1
print_summary
