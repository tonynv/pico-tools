#!/usr/bin/env bash
# remove_pico_tools.sh - undo everything setup_pico_tools.sh installed.
#
# Shows what is present, asks for confirmation, then removes it:
# the Python environment, PicoScope 7 and every Pico driver package,
# all Pico apt repository configuration and signing keys, and the
# leftover USB / library configuration.
#
# Idempotent: anything already gone is skipped.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "$REPO_DIR/lib/ui.sh"

VENV_DIR="$HOME/picoscope-env"
WRAPPERS_CLONE="$HOME/picosdk-python-wrappers"
CMD_LINK="$HOME/.local/bin/pico-tools"
PICO_HOST='labs\.picotech\.com'
APT_SOURCES_DIR=/etc/apt/sources.list.d
APT_MAIN_LIST=/etc/apt/sources.list
KEYRING_DIRS=(/usr/share/keyrings /etc/apt/keyrings /etc/apt/trusted.gpg.d)
UDEV_RULE=/etc/udev/rules.d/95-pico.rules
LD_CONF=/etc/ld.so.conf.d/picoscope.conf
PICO_ROOT=/opt/picoscope

# Pico packages are found by their maintainer address. These names are also
# matched in case a package is ever published with different metadata.
# Nothing from Ubuntu with a similar name (for example libpsl5) is touched.
KNOWN_PICO_PKGS=(picoscope libpicocv libpicoipp libpsospa
    libps2000 libps2000a libps3000 libps3000a libps4000 libps4000a
    libps5000 libps5000a libps6000 libps6000a)

ASSUME_YES=0
PYTHON_ONLY=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Remove PicoScope 7, all Pico drivers, the Pico apt repository configuration,
the USB rule and the Python environment.

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

# --- Discovery ----------------------------------------------------------------
# Installed packages, plus removed ones that still have config files (rc).
find_pico_pkgs() {
    local known=" ${KNOWN_PICO_PKGS[*]} "
    dpkg-query -W -f='${Package}\t${db:Status-Abbrev}\t${Maintainer}\n' 2>/dev/null \
        | awk -F'\t' -v known="$known" '
            ($2 ~ /^(ii|iU|iF|rc)/) && ($3 ~ /@picotech\.com/ || index(known, " " $1 " ")) { print $1 }'
}

# Any apt source file that points at Pico's repository (.list or .sources).
find_repo_files() {
    [[ -d $APT_SOURCES_DIR ]] || return 0
    grep -rlE "$PICO_HOST" "$APT_SOURCES_DIR" 2>/dev/null || true
}

main_list_has_pico() {
    [[ -f $APT_MAIN_LIST ]] && grep -qE "$PICO_HOST" "$APT_MAIN_LIST"
}

# Keyrings named after Pico, plus any keyring a Pico source says it is signed by.
find_keyrings() {
    {
        local dir
        for dir in "${KEYRING_DIRS[@]}"; do
            compgen -G "$dir/*picotech*" || true
        done
        local f
        for f in "${repo_files[@]}"; do
            grep -oE '(signed-by=|Signed-By:[[:space:]]*)/[^] ]+' "$f" | sed -E 's/^(signed-by=|Signed-By:[[:space:]]*)//' || true
        done
    } | sort -u | while read -r k; do [[ -e $k ]] && echo "$k"; done
    return 0
}

# --- Step helpers (run behind the spinner) -----------------------------------
purge_pkgs()      { sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"; }
sudo_rm()         { sudo rm -f -- "$@"; }
strip_main_list() { sudo sed -i.pico-tools.bak -E "/$PICO_HOST/d" "$APT_MAIN_LIST"; }
apt_update()      { sudo apt-get update; }
remove_udev()     { sudo rm -f "$UDEV_RULE" && sudo udevadm control --reload-rules; }
remove_ld()       { sudo rm -f "$LD_CONF" && sudo ldconfig; }
remove_root()     { sudo rm -rf -- "$PICO_ROOT"; }

# --- Take stock ---------------------------------------------------------------
UI_TOTAL_STEPS=$(( PYTHON_ONLY ? 1 : 5 ))
ui_banner "Remove"

pkgs=() repo_files=() keyrings=()
if (( ! PYTHON_ONLY )); then
    mapfile -t pkgs < <(find_pico_pkgs)
    mapfile -t repo_files < <(find_repo_files)
    mapfile -t keyrings < <(find_keyrings)
fi

printf '\n  %sFound on this system:%s\n\n' "$C_BOLD" "$C_RESET"
present=0
show() { # show yes|no <label>
    if [[ $1 == yes ]]; then
        printf '    %s●%s %s\n' "$C_YELLOW" "$C_RESET" "$2"
        present=$((present + 1))
    else
        printf '    %s○ %s (not present)%s\n' "$C_DIM" "$2" "$C_RESET"
    fi
}
exists() { [[ -e $1 ]] && echo yes || echo no; }
# Only the link setup created (pointing into our venv), never another pico-tools install
our_link() { [[ -L $CMD_LINK && $(readlink "$CMD_LINK") == "$VENV_DIR/bin/pico-tools" ]]; }

show "$(exists "$VENV_DIR")" "Python environment      $VENV_DIR"
show "$(exists "$WRAPPERS_CLONE")" "PicoSDK wrapper clone   $WRAPPERS_CLONE"
show "$(our_link && echo yes || echo no)" "pico-tools command     $CMD_LINK"
if (( ! PYTHON_ONLY )); then
    if (( ${#pkgs[@]} )); then
        show yes "Pico packages (${#pkgs[@]})     ${pkgs[*]}"
    else
        show no "Pico packages / drivers"
    fi
    if (( ${#repo_files[@]} )); then
        for f in "${repo_files[@]}"; do show yes "Pico apt source         $f"; done
    else
        show no "Pico apt source         $APT_SOURCES_DIR/picoscope*.list"
    fi
    main_list_has_pico && show yes "Pico entry in           $APT_MAIN_LIST"
    if (( ${#keyrings[@]} )); then
        for f in "${keyrings[@]}"; do show yes "Pico signing key        $f"; done
    else
        show no "Pico signing key"
    fi
    show "$(exists "$UDEV_RULE")" "USB udev rule           $UDEV_RULE"
    show "$(exists "$LD_CONF")" "Library path            $LD_CONF"
    show "$(exists "$PICO_ROOT")" "Install folder          $PICO_ROOT"
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

if pgrep -f "$PICO_ROOT/" >/dev/null 2>&1; then
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
if our_link; then
    ui_run "Removing $CMD_LINK" rm -f "$CMD_LINK"
else
    ui_item skip "pico-tools command link" "not present"
fi
if [[ -d $WRAPPERS_CLONE ]]; then
    ui_run "Deleting $WRAPPERS_CLONE" rm -rf "$WRAPPERS_CLONE"
else
    ui_item skip "PicoSDK wrapper clone" "not present"
fi

if (( ! PYTHON_ONLY )); then
    # 2. Packages (before the repo, so apt still knows where they came from)
    ui_step "Uninstalling PicoScope 7 and drivers"
    if (( ${#pkgs[@]} )); then
        ui_run "Purging ${#pkgs[@]} Pico package(s)" purge_pkgs "${pkgs[@]}"
    else
        ui_item skip "Pico packages" "not installed"
    fi

    # 3. Repository configuration
    ui_step "Removing the Pico apt repository configuration"
    repo_changed=0
    if (( ${#repo_files[@]} )); then
        ui_run "Removing ${#repo_files[@]} apt source file(s)" sudo_rm "${repo_files[@]}"
        repo_changed=1
    else
        ui_item skip "Apt source files" "not present"
    fi
    if main_list_has_pico; then
        ui_run "Removing Pico lines from sources.list" strip_main_list
        repo_changed=1
    fi
    if (( ${#keyrings[@]} )); then
        ui_run "Removing ${#keyrings[@]} signing key(s)" sudo_rm "${keyrings[@]}"
        repo_changed=1
    else
        ui_item skip "Signing keys" "not present"
    fi
    if (( repo_changed )); then
        ui_run "Refreshing package lists" apt_update
    fi

    # 4. Leftovers
    ui_step "Removing leftover system configuration"
    if [[ -e $UDEV_RULE ]]; then
        ui_run "Removing USB udev rule" remove_udev
    else
        ui_item skip "USB udev rule" "not present"
    fi
    if [[ -e $LD_CONF ]]; then
        ui_run "Removing library path" remove_ld
    else
        ui_item skip "Library path" "not present"
    fi
    if [[ -e $PICO_ROOT ]]; then
        ui_run "Deleting $PICO_ROOT" remove_root
    else
        ui_item skip "Install folder" "not present"
    fi

    # 5. Verify
    ui_step "Verifying"
    failed=0
    check() { # check <label> <command...>  (command succeeds when clean)
        local label=$1; shift
        if "$@"; then ui_item ok "$label"; else ui_item fail "$label" "still present"; failed=1; fi
    }
    no_pkgs()    { [[ -z $(find_pico_pkgs) ]]; }
    no_sources() { [[ -z $(find_repo_files) ]] && ! main_list_has_pico; }
    no_driver()  { ! ldconfig -p | grep -E '(libps[0-9]+[a-z]*|libpsospa|libpicoipp)\.so' > /dev/null; }
    no_files()   { [[ ! -e $UDEV_RULE && ! -e $LD_CONF && ! -e $PICO_ROOT ]]; }
    check "No Pico packages installed" no_pkgs
    check "No Pico apt sources configured" no_sources
    check "Driver libraries unloaded" no_driver
    check "No leftover Pico files" no_files
    (( failed )) && ui_die "Some items could not be removed. Log: $UI_LOG"
fi

ui_summary "PicoScope tools removed" \
    "" \
    "Run ./setup_pico_tools.sh at any time to install again." \
    ""
