#!/usr/bin/env bash
# remove_pico_tools.sh - undo everything setup_pico_tools.sh installed.
#
# Shows what is present, asks for confirmation, then removes it.
# Idempotent: anything already gone is skipped.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "$REPO_DIR/lib/ui.sh"

VENV_DIR="$HOME/picoscope-env"
WRAPPERS_CLONE="$HOME/picosdk-python-wrappers"
KEYRING=/usr/share/keyrings/picotech-archive-keyring.gpg
REPO_LIST=/etc/apt/sources.list.d/picoscope7.list
UDEV_RULE=/etc/udev/rules.d/95-pico.rules
LD_CONF=/etc/ld.so.conf.d/picoscope.conf

# Only packages published by Pico Technology. Listed explicitly so nothing
# from Ubuntu with a similar name (for example libpsl5) is ever touched.
KNOWN_PICO_PKGS=(picoscope libpicocv libpicoipp libpsospa
    libps2000 libps2000a libps3000 libps3000a libps4000 libps4000a
    libps5000 libps5000a libps6000 libps6000a)

ASSUME_YES=0
PYTHON_ONLY=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Remove PicoScope 7, the Pico drivers, repository, USB rule and Python env.

Options:
  --python-only   Only remove the Python environment (keep PicoScope 7)
  -y, --yes       Do not ask for confirmation
  -h, --help      Show this help
EOF
}

while (( $# )); do
    case $1 in
        --python-only) PYTHON_ONLY=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; ui_die "Unknown option: $1" ;;
    esac
    shift
done

# --- Step helpers (run behind the spinner) -----------------------------------
purge_pkgs()   { sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"; }
sudo_rm()      { sudo rm -f "$@"; }
reload_udev()  { sudo rm -f "$UDEV_RULE" && sudo udevadm control --reload-rules; }
reload_ld()    { sudo rm -f "$LD_CONF" && sudo ldconfig; }
apt_update()   { sudo apt-get update; }

installed_pico_pkgs() {
    local pkg
    for pkg in "${KNOWN_PICO_PKGS[@]}"; do
        pkg_installed "$pkg" && echo "$pkg"
    done
    return 0
}

# --- Take stock ---------------------------------------------------------------
UI_TOTAL_STEPS=$(( PYTHON_ONLY ? 1 : 4 ))
ui_banner "Remove"

mapfile -t pkgs < <(installed_pico_pkgs)

printf '\n  %sFound on this system:%s\n\n' "$C_BOLD" "$C_RESET"
present=0
show() { # show <path-or-flag> <label>
    if [[ $1 == yes || -e $1 ]]; then
        printf '    %s●%s %s\n' "$C_YELLOW" "$C_RESET" "$2"
        present=$((present + 1))
    else
        printf '    %s○ %s (not present)%s\n' "$C_DIM" "$2" "$C_RESET"
    fi
}
show "$VENV_DIR" "Python environment  $VENV_DIR"
show "$WRAPPERS_CLONE" "PicoSDK wrapper clone  $WRAPPERS_CLONE"
if (( ! PYTHON_ONLY )); then
    show "$UDEV_RULE" "USB udev rule  $UDEV_RULE"
    show "$LD_CONF" "Library path  $LD_CONF"
    show "$([[ ${#pkgs[@]} -gt 0 ]] && echo yes || echo no)" "Packages  ${pkgs[*]:-picoscope, libps*}"
    show "$REPO_LIST" "Pico repository  $REPO_LIST"
    show "$KEYRING" "Pico signing key  $KEYRING"
fi

if (( present == 0 )); then
    ui_summary "Nothing to remove - already clean" ""
    exit 0
fi

if (( ! ASSUME_YES )); then
    printf '\n  %sRemove the %d item(s) marked ●? [y/N]%s ' "$C_BOLD" "$present" "$C_RESET"
    { read -r answer < /dev/tty; } 2>/dev/null || answer=
    [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]] || { printf '\n  Cancelled. Nothing was changed.\n\n'; exit 0; }
fi

if pgrep -f '/opt/picoscope/' >/dev/null 2>&1; then
    ui_item warn "PicoScope 7 appears to be running" "close it first"
fi

(( PYTHON_ONLY )) || ui_sudo_keepalive

# 1. Python
ui_step "Removing the Python environment"
if [[ -d $VENV_DIR ]]; then
    ui_run "Deleting $VENV_DIR" rm -rf "$VENV_DIR"
else
    ui_item skip "Virtual environment" "not present"
fi
if [[ -d $WRAPPERS_CLONE ]]; then
    ui_run "Deleting $WRAPPERS_CLONE" rm -rf "$WRAPPERS_CLONE"
else
    ui_item skip "PicoSDK wrapper clone" "not present"
fi

if (( ! PYTHON_ONLY )); then
    # 2. System configuration
    ui_step "Removing USB and library configuration"
    if [[ -e $UDEV_RULE ]]; then
        ui_run "Removing USB udev rule" reload_udev
    else
        ui_item skip "USB udev rule" "not present"
    fi
    if [[ -e $LD_CONF ]]; then
        ui_run "Removing library path" reload_ld
    else
        ui_item skip "Library path" "not present"
    fi

    # 3. Packages
    ui_step "Uninstalling PicoScope 7 and drivers"
    if (( ${#pkgs[@]} )); then
        ui_run "Purging ${#pkgs[@]} Pico package(s)" purge_pkgs "${pkgs[@]}"
    else
        ui_item skip "Pico packages" "not installed"
    fi

    # 4. Repository
    ui_step "Removing the Pico Technology repository"
    if [[ -e $REPO_LIST || -e $KEYRING ]]; then
        ui_run "Removing repository and signing key" sudo_rm "$REPO_LIST" "$KEYRING"
        ui_run "Refreshing package lists" apt_update
    else
        ui_item skip "Repository and signing key" "not present"
    fi
fi

ui_summary "PicoScope tools removed" \
    "" \
    "Run ./setup_pico_tools.sh at any time to install again." \
    ""
