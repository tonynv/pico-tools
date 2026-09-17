# shellcheck shell=bash
# Shared terminal styling for pico-tools scripts.
# Source this file; it does not run anything on its own.

# --- Colors (disabled when not a terminal or NO_COLOR is set) ----------------
if [[ -t 1 && -z ${NO_COLOR:-} ]] && (( $(tput colors 2>/dev/null || echo 0) >= 256 )); then
    C_RESET=$'\e[0m'   C_BOLD=$'\e[1m'    C_DIM=$'\e[2m'
    C_RED=$'\e[38;5;203m'  C_GREEN=$'\e[38;5;114m' C_YELLOW=$'\e[38;5;221m'
    C_BLUE=$'\e[38;5;75m'  C_CYAN=$'\e[38;5;80m'   C_GREY=$'\e[38;5;245m'
    GRADIENT=($'\e[38;5;27m' $'\e[38;5;33m' $'\e[38;5;39m' $'\e[38;5;45m' $'\e[38;5;51m' $'\e[38;5;87m')
    UI_FANCY=1
else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_GREY=''
    GRADIENT=('' '' '' '' '' '')
    UI_FANCY=0
fi

UI_STEP=0
UI_TOTAL_STEPS=0
UI_START=$SECONDS
UI_LOG=${UI_LOG:-"${XDG_CACHE_HOME:-$HOME/.cache}/pico-tools/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"}
mkdir -p "$(dirname "$UI_LOG")"
: > "$UI_LOG"

# --- Banner -------------------------------------------------------------------
ui_banner() {
    local subtitle=$1
    local art=(
        '  ██████╗ ██╗ ██████╗ ██████╗     ████████╗ ██████╗  ██████╗ ██╗     ███████╗'
        '  ██╔══██╗██║██╔════╝██╔═══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝'
        '  ██████╔╝██║██║     ██║   ██║       ██║   ██║   ██║██║   ██║██║     ███████╗'
        '  ██╔═══╝ ██║██║     ██║   ██║       ██║   ██║   ██║██║   ██║██║     ╚════██║'
        '  ██║     ██║╚██████╗╚██████╔╝       ██║   ╚██████╔╝╚██████╔╝███████╗███████║'
        '  ╚═╝     ╚═╝ ╚═════╝ ╚═════╝        ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝'
    )
    echo
    local i
    for i in "${!art[@]}"; do
        printf '%s%s%s\n' "${GRADIENT[$i]}" "${art[$i]}" "$C_RESET"
    done
    # A little scope trace under the logo
    local wave='  ▁▂▃▅▆▇█▇▆▅▃▂▁▁▂▃▅▆▇█▇▆▅▃▂▁▁▂▃▅▆▇█▇▆▅▃▂▁▁▂▃▅▆▇█▇▆▅▃▂▁▁▂▃▅▆▇█▇▆▅▃▂▁▁▂▃▅▆▇█▇'
    printf '%s%s%s\n\n' "$C_CYAN" "$wave" "$C_RESET"
    printf '  %s%s%s  %s·%s  %sPicoScope 4225A on Ubuntu%s\n' \
        "$C_BOLD" "$subtitle" "$C_RESET" "$C_GREY" "$C_RESET" "$C_GREY" "$C_RESET"
    printf '  %sLog: %s%s\n' "$C_DIM" "$UI_LOG" "$C_RESET"
}

# --- Structure ----------------------------------------------------------------
ui_step() {
    UI_STEP=$((UI_STEP + 1))
    local title=$1
    local label
    label=$(printf '[%d/%d]' "$UI_STEP" "$UI_TOTAL_STEPS")
    printf '\n%s%s%s %s%s%s\n' "$C_BLUE$C_BOLD" "$label" "$C_RESET" "$C_BOLD" "$title" "$C_RESET"
    printf '%s  %s%s\n' "$C_GREY" "────────────────────────────────────────────────────────────────" "$C_RESET"
}

# ui_item <status> <label> [detail]   status: ok | skip | warn | fail | info
ui_item() {
    local status=$1 label=$2 detail=${3:-}
    local icon color
    case $status in
        ok)   icon='✔' color=$C_GREEN ;;
        skip) icon='✔' color=$C_GREY ;;
        warn) icon='!' color=$C_YELLOW ;;
        fail) icon='✖' color=$C_RED ;;
        *)    icon='•' color=$C_CYAN ;;
    esac
    if [[ $status == skip ]]; then
        printf '  %s%s%s %-38s %s%s%s\n' "$color" "$icon" "$C_RESET" "$label" "$C_DIM" "${detail:-already done}" "$C_RESET"
    else
        printf '  %s%s%s %-38s %s%s%s\n' "$color" "$icon" "$C_RESET" "$label" "$C_GREY" "$detail" "$C_RESET"
    fi
}

# ui_run <label> <command...>
# Runs a command with a spinner, sending its output to the log file.
ui_run() {
    local label=$1; shift
    printf '\n### %s\n$ %s\n' "$label" "$*" >> "$UI_LOG"

    if (( ! UI_FANCY )); then
        printf '  • %s ...\n' "$label"
        if "$@" >> "$UI_LOG" 2>&1; then ui_item ok "$label"; return 0; fi
        ui_item fail "$label"; ui_log_tail; return 1
    fi

    "$@" >> "$UI_LOG" 2>&1 &
    local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 start=$SECONDS
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s %-38s %s%ss%s' "$C_CYAN" "${frames:i++%${#frames}:1}" "$C_RESET" \
            "$label" "$C_DIM" "$((SECONDS - start))" "$C_RESET"
        sleep 0.08
    done
    tput cnorm 2>/dev/null || true
    printf '\r\e[K'

    if wait "$pid"; then
        ui_item ok "$label" "$((SECONDS - start))s"
    else
        ui_item fail "$label"
        ui_log_tail
        return 1
    fi
}

ui_log_tail() {
    printf '\n  %sLast lines of %s:%s\n' "$C_RED" "$UI_LOG" "$C_RESET"
    tail -n 15 "$UI_LOG" | sed "s/^/    ${C_GREY}│${C_RESET} /"
    echo
}

ui_die() {
    printf '\n  %s✖ %s%s\n\n' "$C_RED$C_BOLD" "$1" "$C_RESET" >&2
    exit 1
}

# ui_summary <title> <line>...
ui_summary() {
    local title=$1; shift
    local elapsed=$((SECONDS - UI_START)) width=68 line
    local bar
    bar=$(printf '%*s' "$width" '' | sed 's/ /─/g')
    printf '\n%s╭%s╮%s\n' "$C_GREEN" "$bar" "$C_RESET"
    printf '%s│%s %s%-*s%s%s│%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" $((width - 1)) \
        "$title  ($((elapsed / 60))m $((elapsed % 60))s)" "$C_RESET" "$C_GREEN" "$C_RESET"
    printf '%s├%s┤%s\n' "$C_GREEN" "$bar" "$C_RESET"
    for line in "$@"; do
        printf '%s│%s %-*s%s│%s\n' "$C_GREEN" "$C_RESET" $((width - 1)) "$line" "$C_GREEN" "$C_RESET"
    done
    printf '%s╰%s╯%s\n\n' "$C_GREEN" "$bar" "$C_RESET"
}

# --- sudo ---------------------------------------------------------------------
# Ask for the password once up front, then keep the credentials fresh so
# commands running behind a spinner never stop to prompt.
ui_sudo_keepalive() {
    if [[ $EUID -eq 0 ]]; then
        ui_die "Run this as your normal user, not with sudo. It will ask for your password."
    fi
    printf '\n  %s🔒 Administrator access is needed for system changes.%s\n' "$C_YELLOW" "$C_RESET"
    sudo -v || ui_die "sudo authentication failed"
    ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
    UI_SUDO_PID=$!
    trap 'kill "$UI_SUDO_PID" 2>/dev/null; tput cnorm 2>/dev/null || true' EXIT
}

# --- Checks -------------------------------------------------------------------
pkg_installed() {
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}
