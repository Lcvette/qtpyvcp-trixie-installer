#!/usr/bin/env bash
# Bare-metal preflight for Raspberry Pi 5 + Debian trixie target stack.
# This script does NOT install LinuxCNC/QtPyVCP/Probe Basic.
# It checks whether the platform and apt repositories look ready.

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
OUT_DIR="${OUT_DIR:-/tmp/pi5_preflight}"
RUN_APT_SIM=1

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

RED='\033[31m'
YELLOW='\033[33m'
GREEN='\033[32m'
BLUE='\033[34m'
RESET='\033[0m'

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--out-dir /tmp/pi5_preflight] [--no-apt-sim]

Options:
  --out-dir PATH     Output directory for logs. Default: /tmp/pi5_preflight
  --no-apt-sim       Skip apt dependency simulation checks.
  -h, --help         Show this help.
EOF
}

log_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}[PASS]${RESET} $*"
}

log_warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

log_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}[FAIL]${RESET} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_pkg_candidate() {
    local pkg="$1"
    local candidate
    candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
        log_pass "Apt candidate available: $pkg ($candidate)"
    else
        log_fail "No apt candidate: $pkg"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out-dir)
                [[ $# -lt 2 ]] && { echo "--out-dir requires a path"; exit 2; }
                OUT_DIR="$2"
                shift 2
                ;;
            --no-apt-sim)
                RUN_APT_SIM=0
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1"
                usage
                exit 2
                ;;
        esac
    done
}

check_platform() {
    local arch kernel distro
    arch="$(uname -m 2>/dev/null || echo unknown)"
    kernel="$(uname -r 2>/dev/null || echo unknown)"
    distro="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"

    log_info "Architecture: $arch"
    log_info "Kernel: $kernel"
    log_info "Distro: $distro"

    if [[ "$arch" == "aarch64" ]]; then
        log_pass "ARM64 architecture detected (Pi 5 target)."
    else
        log_warn "Non-ARM64 architecture ($arch). Script still useful for repo preflight only."
    fi

    if [[ "$distro" == *"trixie"* || "$distro" == *"Debian GNU/Linux 13"* ]]; then
        log_pass "Debian trixie detected."
    else
        log_warn "Non-trixie distro detected. Confirm package names and versions manually."
    fi

    if [[ "$kernel" == *"rt"* || "$kernel" == *"PREEMPT_RT"* ]]; then
        log_pass "RT-flavored kernel string detected ($kernel)."
    else
        log_warn "RT kernel not detected from kernel string."
    fi

    if [[ -f /sys/kernel/realtime ]]; then
        if [[ "$(cat /sys/kernel/realtime 2>/dev/null)" == "1" ]]; then
            log_pass "Kernel realtime mode reports 1"
        else
            log_warn "Kernel realtime mode reports 0"
        fi
    else
        log_warn "/sys/kernel/realtime missing"
    fi
}

check_graphics() {
    if ! have_cmd glxinfo; then
        log_warn "glxinfo missing (install mesa-utils to test OpenGL renderer)."
        return
    fi

    if glxinfo -B >"$OUT_DIR/glxinfo_B.txt" 2>&1; then
        log_pass "glxinfo -B succeeded (see $OUT_DIR/glxinfo_B.txt)"
        if grep -Eqi "llvmpipe|software rasterizer" "$OUT_DIR/glxinfo_B.txt"; then
            log_warn "Software rendering detected (llvmpipe/software rasterizer)."
        else
            log_pass "No software rasterizer signature detected."
        fi
    else
        log_warn "glxinfo -B failed (see $OUT_DIR/glxinfo_B.txt)"
    fi
}

check_repos_and_packages() {
    if ! have_cmd apt-cache; then
        log_fail "apt-cache not available; cannot validate repository candidates."
        return
    fi

    check_pkg_candidate "linuxcnc-uspace"
    check_pkg_candidate "python3-pyside6.qtcore"
    check_pkg_candidate "python3-pyside6.qtwidgets"
    check_pkg_candidate "python3-pyside6.qtuitools"
    check_pkg_candidate "python3-vtk9"
    check_pkg_candidate "python3-pyqtgraph"
    check_pkg_candidate "python3-simpleeval"
}

run_apt_simulations() {
    if [[ "$RUN_APT_SIM" -ne 1 ]]; then
        log_info "Skipping apt simulation checks (--no-apt-sim)."
        return
    fi

    if ! have_cmd apt-get; then
        log_fail "apt-get not available; cannot run install simulation."
        return
    fi

    # Simulate core runtime stack install without making changes.
    if apt-get -s install \
        linuxcnc-uspace \
        python3-pyside6.qtcore \
        python3-pyside6.qtdbus \
        python3-pyside6.qtwidgets \
        python3-pyside6.qtuitools \
        python3-pyside6.qtopengl \
        python3-vtk9 \
        python3-pyqtgraph \
        python3-simpleeval \
        >"$OUT_DIR/apt_sim_core.txt" 2>&1; then
        log_pass "apt simulation passed for core runtime stack (see $OUT_DIR/apt_sim_core.txt)"
    else
        log_fail "apt simulation failed for core runtime stack (see $OUT_DIR/apt_sim_core.txt)"
    fi

    # Simulate optional tools for diagnostics.
    if apt-get -s install mesa-utils rt-tests >"$OUT_DIR/apt_sim_tools.txt" 2>&1; then
        log_pass "apt simulation passed for diagnostic tools (see $OUT_DIR/apt_sim_tools.txt)"
    else
        log_warn "apt simulation failed for diagnostic tools (see $OUT_DIR/apt_sim_tools.txt)"
    fi
}

print_summary() {
    echo
    echo "====================="
    echo "Preflight Summary"
    echo "====================="
    echo "PASS: $PASS_COUNT"
    echo "WARN: $WARN_COUNT"
    echo "FAIL: $FAIL_COUNT"
    echo "Logs: $OUT_DIR"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo
        echo "Result: FAIL"
        exit 1
    elif [[ $WARN_COUNT -gt 0 ]]; then
        echo
        echo "Result: WARN"
        exit 0
    else
        echo
        echo "Result: PASS"
        exit 0
    fi
}

main() {
    parse_args "$@"

    mkdir -p "$OUT_DIR"
    log_info "Writing logs to $OUT_DIR"

    check_platform
    check_graphics
    check_repos_and_packages
    run_apt_simulations
    print_summary
}

main "$@"
