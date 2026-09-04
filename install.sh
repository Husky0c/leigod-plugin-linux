#!/bin/sh
set -e

VERSION="1.2.2.15"
BASE="/opt/leigod"
SERVICE_FILE="/etc/systemd/system/leigod_plugin.service"
SCRIPT_DIR="$(CDPATH= cd -P "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then error "Please run as root (sudo ./install.sh)"; fi

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then error "Only x86_64 supported, current: $ARCH"; fi

if ! command -v systemctl >/dev/null 2>&1; then
    error "systemd not found. This package requires systemd."
fi

detect_pkg_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"; PKG_INSTALL="apt install -y"; PKG_UPDATE="apt update"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"; PKG_INSTALL="dnf install -y"; PKG_UPDATE="dnf check-update || true"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"; PKG_INSTALL="yum install -y"; PKG_UPDATE="yum makecache"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"; PKG_INSTALL="zypper install -y"; PKG_UPDATE="zypper refresh"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"; PKG_INSTALL="pacman -S --noconfirm"; PKG_UPDATE="pacman -Sy"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"; PKG_INSTALL="apk add"; PKG_UPDATE="apk update"
    else
        warn "Cannot detect package manager. Please manually install: ipset curl"
        PKG_MANAGER="manual"
    fi
    info "Detected package manager: $PKG_MANAGER"
}

install_deps() {
    if [ "$PKG_MANAGER" = "manual" ]; then return; fi
    info "Updating package lists..."
    $PKG_UPDATE >/dev/null 2>&1 || true
    info "Installing dependencies: ipset curl..."
    $PKG_INSTALL ipset curl >/dev/null 2>&1 || error "Failed to install dependencies"
    info "Dependencies installed."
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

stop_existing_service() {
    if systemctl is-active --quiet leigod_plugin.service 2>/dev/null; then
        info "Stopping existing Leigod service before replacing files..."
        systemctl stop leigod_plugin.service \
            || error "Failed to stop existing Leigod service"
    fi
}

install_files() {
    info "Installing files to $BASE..."
    mkdir -p "$BASE/config"
    cp "$SCRIPT_DIR/opt/leigod/steamdeck_acc_monitor.sh" "$BASE/"
    cp "$SCRIPT_DIR/opt/leigod/leigod_uninstall.sh" "$BASE/"
    cp "$SCRIPT_DIR/opt/leigod/fake_os-release" "$BASE/"
    cp "$SCRIPT_DIR/opt/leigod/fake_product_name" "$BASE/"
    cp "$SCRIPT_DIR/opt/leigod/config/acc_version.ini" "$BASE/config/"
    cp "$SCRIPT_DIR/opt/leigod/config/accelerator.ini" "$BASE/config/"
    cp "$SCRIPT_DIR/opt/leigod/config/new_upgrade_conf.json" "$BASE/config/"
    : > "$BASE/config/accelerator"
    chmod 755 "$BASE/steamdeck_acc_monitor.sh" "$BASE/leigod_uninstall.sh"
    info "Files installed."
}

create_symlink() {
    if [ -d /home/leigod ] && [ ! -L /home/leigod ]; then
        if rmdir /home/leigod 2>/dev/null; then
            info "Removed empty directory /home/leigod"
        else
            warn "/home/leigod is a non-empty directory. Please move it manually."
        fi
    fi
    if [ ! -L /home/leigod ]; then
        ln -sf "$BASE" /home/leigod
        info "Created symlink /home/leigod -> $BASE"
    fi
}

setup_service() {
    info "Creating systemd service..."
    cat > "$SERVICE_FILE" << 'SERVICEEOF'
[Unit]
Description=Leigod Plugin Service
Wants=network-online.target
After=network.target network-online.target

[Service]
ExecStart=/opt/leigod/steamdeck_acc_monitor.sh
KillMode=control-group
Restart=always
RestartSec=3
BindReadOnlyPaths=/opt/leigod/fake_product_name:/sys/class/dmi/id/product_name
BindReadOnlyPaths=/opt/leigod/fake_os-release:/etc/os-release

[Install]
WantedBy=default.target
SERVICEEOF
    systemctl daemon-reload
    systemctl enable leigod_plugin.service
    info "Service enabled (will auto-start on boot)."
}

start_service() {
    info "Starting Leigod Plugin Service..."
    systemctl restart leigod_plugin.service \
        || error "Failed to start Leigod Plugin Service"
    sleep 2
    if systemctl is-active --quiet leigod_plugin.service; then
        info "Service is running."
    else
        warn "Service is not running. Check: systemctl status leigod_plugin.service"
    fi
}

print_summary() {
    echo ""
    echo "============================================"
    echo " Leigod Plugin v$VERSION installed!"
    echo "============================================"
    echo ""
    echo " Next steps:"
    echo "   1. Open the Leigod mobile app"
    echo "   2. Bind the device (scan QR code)"
    echo "   3. Start acceleration"
    echo ""
    echo " Manage: systemctl {status|restart|stop} leigod_plugin.service"
    echo " Uninstall: sudo ./uninstall.sh"
    echo ""
}

echo ""; echo "Leigod Plugin v$VERSION Installer"; echo "============================================"; echo ""
detect_pkg_manager; install_deps; stop_existing_service; install_files; download_binaries; create_symlink; setup_service; start_service; print_summary
