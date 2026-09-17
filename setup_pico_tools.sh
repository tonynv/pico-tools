#!/usr/bin/env bash
# setup_pico_tools.sh - install and configure a PicoScope 4225A on Ubuntu.
#
# Updates Ubuntu, adds the Pico Technology apt repository, installs
# PicoScope 7 and the ps4000a driver, sets USB permissions and creates a
# Python virtual environment for the pico-tools package (pip install pico-tools).
#
# Idempotent: re-running only does the work that is still missing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "$REPO_DIR/lib/ui.sh"

VENV_DIR="$HOME/picoscope-env"
KEYRING=/usr/share/keyrings/picotech-archive-keyring.gpg
KEY_URL=https://labs.picotech.com/Release.gpg.key
REPO_LIST=/etc/apt/sources.list.d/picoscope7.list
REPO_LINE="deb [arch=amd64 signed-by=$KEYRING] https://labs.picotech.com/picoscope7/debian/ picoscope main"
UDEV_RULE=/etc/udev/rules.d/95-pico.rules
UDEV_LINE='ATTRS{idVendor}=="0ce9", MODE="0666"'
LD_CONF=/etc/ld.so.conf.d/picoscope.conf
PICO_LIB=/opt/picoscope/lib

PREREQS=(ca-certificates curl gnupg git python3 python3-venv python3-pip usbutils)
PICO_PKGS=(picoscope libps4000a libpicoipp)

SKIP_UPGRADE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Install and configure PicoScope 7, the 4225A driver and Python tools.

Options:
  --skip-upgrade   Do not run a full Ubuntu upgrade (still installs prerequisites)
  -h, --help       Show this help
EOF
}

while (( $# )); do
    case $1 in
        --skip-upgrade) SKIP_UPGRADE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; ui_die "Unknown option: $1" ;;
    esac
    shift
done

# --- Step helpers (run behind the spinner) -----------------------------------
apt_update()      { sudo apt-get update; }
apt_upgrade()     { sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade; }
apt_install()     { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
install_key()     { curl -fsSL "$KEY_URL" | gpg --dearmor | sudo tee "$KEYRING" > /dev/null; }
write_repo()      { echo "$REPO_LINE" | sudo tee "$REPO_LIST" > /dev/null; }
write_udev()      { echo "$UDEV_LINE" | sudo tee "$UDEV_RULE" > /dev/null \
                        && sudo udevadm control --reload-rules && sudo udevadm trigger; }
register_libs()   { echo "$PICO_LIB" | sudo tee "$LD_CONF" > /dev/null && sudo ldconfig; }
create_venv()     { python3 -m venv "$VENV_DIR"; }
upgrade_pip()     { "$VENV_DIR/bin/pip" install --upgrade pip; }

missing_pkgs() {
    local pkg
    for pkg in "$@"; do pkg_installed "$pkg" || echo "$pkg"; done
}

file_has() { [[ -f $1 && $(cat "$1") == "$2" ]]; }


# --- Go -----------------------------------------------------------------------
UI_TOTAL_STEPS=7
ui_banner "Setup"
ui_sudo_keepalive

# 1. Pre-flight
ui_step "Checking this system"
# shellcheck source=/dev/null
. /etc/os-release
if [[ ${ID:-} == ubuntu ]]; then
    ui_item ok "Ubuntu detected" "$PRETTY_NAME"
else
    ui_item warn "Not Ubuntu" "${PRETTY_NAME:-unknown} (continuing anyway)"
fi
arch=$(dpkg --print-architecture)
[[ $arch == amd64 ]] || ui_die "Pico's repository only provides amd64 packages (this machine is $arch)."
ui_item ok "Architecture" "$arch"
if pgrep -x PicoScope >/dev/null 2>&1 || pgrep -f '/opt/picoscope/bin/PicoScope' >/dev/null 2>&1; then
    ui_item warn "PicoScope 7 is running" "close it before testing with Python"
fi

# 2. Ubuntu
ui_step "Updating Ubuntu"
ui_run "Refreshing package lists" apt_update
if (( SKIP_UPGRADE )); then
    ui_item skip "Full system upgrade" "skipped (--skip-upgrade)"
else
    ui_run "Upgrading installed packages" apt_upgrade
fi
mapfile -t need < <(missing_pkgs "${PREREQS[@]}")
if (( ${#need[@]} )); then
    ui_run "Installing prerequisites (${#need[@]})" apt_install "${need[@]}"
else
    ui_item skip "Prerequisites" "already installed"
fi

# 3. Pico repository
ui_step "Adding the Pico Technology repository"
repo_changed=0
if [[ -s $KEYRING ]]; then
    ui_item skip "Signing key"
else
    ui_run "Downloading signing key" install_key
    repo_changed=1
fi
if file_has "$REPO_LIST" "$REPO_LINE"; then
    ui_item skip "Repository entry"
else
    ui_run "Adding repository entry" write_repo
    repo_changed=1
fi
if (( repo_changed )); then
    ui_run "Refreshing package lists" apt_update
fi

# 4. PicoScope 7 + drivers
ui_step "Installing PicoScope 7 and drivers"
mapfile -t need < <(missing_pkgs "${PICO_PKGS[@]}")
if (( ${#need[@]} )); then
    ui_run "Installing ${need[*]}" apt_install "${need[@]}"
else
    ui_item skip "PicoScope 7, libps4000a, libpicoipp" "already installed"
fi
ui_item info "PicoScope version" "$(dpkg-query -W -f='${Version}' picoscope)"

# 5. System configuration
ui_step "Configuring USB access and libraries"
if file_has "$UDEV_RULE" "$UDEV_LINE"; then
    ui_item skip "USB udev rule"
else
    ui_run "Installing USB udev rule" write_udev
    ui_item info "Replug the scope" "so the new permissions apply"
fi
if ldconfig -p | grep -q 'libps4000a\.so'; then
    ui_item skip "Driver library path"
else
    ui_run "Registering $PICO_LIB" register_libs
fi

# 6. Python
ui_step "Creating the Python environment"
if [[ -x $VENV_DIR/bin/python ]]; then
    ui_item skip "Virtual environment" "$VENV_DIR"
else
    ui_run "Creating virtual environment" create_venv
    ui_run "Upgrading pip" upgrade_pip
fi

# 7. Verify
ui_step "Verifying"
failed=0
if ldconfig -p | grep -q 'libps4000a\.so'; then
    ui_item ok "ps4000a driver library installed"
else
    ui_item fail "ps4000a driver library installed" "see log"
    failed=1
fi
if [[ -x $VENV_DIR/bin/pip ]]; then
    ui_item ok "Python environment ready" "$VENV_DIR"
else
    ui_item fail "Python environment ready" "see log"
    failed=1
fi
if lsusb 2>/dev/null | grep -qi 'ID 0ce9:'; then
    ui_item ok "PicoScope connected over USB"
else
    ui_item warn "No PicoScope found on USB" "plug it in to test"
fi

(( failed )) && ui_die "Setup finished with errors. Log: $UI_LOG"

ui_summary "PicoScope driver is ready - install pico-tools next" \
    "" \
    "1. source ~/picoscope-env/bin/activate" \
    "2. pip install pico-tools      (or: pip install . in this repo)" \
    "3. Close PicoScope 7, then run:  pico-tools test" \
    ""
