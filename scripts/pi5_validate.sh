#!/usr/bin/env bash
# Quick validator for LinuxCNC + QtPyVCP + Probe Basic environments.
# Intended for Raspberry Pi 5 (arm64, Debian trixie) but safe on other hosts.

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
OUT_DIR="${OUT_DIR:-/tmp/pi5_validate}"
INI_PATH=""
RUN_LINUXCNC=0

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
Usage: $SCRIPT_NAME [--ini /path/to/config.ini] [--run-linuxcnc] [--out-dir /tmp/pi5_validate]

Options:
  --ini PATH         LinuxCNC INI file to validate/launch.
  --run-linuxcnc     Attempt non-interactive LinuxCNC launch check with the INI.
  --out-dir PATH     Output directory for logs. Default: /tmp/pi5_validate
  -h, --help         Show this help.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --ini /home/pi/configs/sim.qtpyvcp/tnc_opcua.ini --run-linuxcnc
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

check_cmd() {
    local cmd="$1"
    local hint="$2"
    if have_cmd "$cmd"; then
        log_pass "Command available: $cmd"
    else
        log_warn "Missing command: $cmd ($hint)"
    fi
}

check_python_import() {
    local mod="$1"
    local label="$2"
    if python3 - <<PY >/dev/null 2>&1
import importlib
importlib.import_module("$mod")
PY
    then
        log_pass "Python import OK: $label ($mod)"
    else
        log_fail "Python import FAILED: $label ($mod)"
    fi
}

check_pkg_installed() {
    local pkg="$1"
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        log_pass "Package installed: $pkg"
    else
        log_warn "Package not installed: $pkg"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ini)
                [[ $# -lt 2 ]] && { echo "--ini requires a path"; exit 2; }
                INI_PATH="$2"
                shift 2
                ;;
            --run-linuxcnc)
                RUN_LINUXCNC=1
                shift
                ;;
            --out-dir)
                [[ $# -lt 2 ]] && { echo "--out-dir requires a path"; exit 2; }
                OUT_DIR="$2"
                shift 2
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

check_system_baseline() {
    local arch kernel distro
    arch="$(uname -m 2>/dev/null || echo unknown)"
    kernel="$(uname -r 2>/dev/null || echo unknown)"
    distro="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"

    log_info "Architecture: $arch"
    log_info "Kernel: $kernel"
    log_info "Distro: $distro"

    if [[ "$arch" == "aarch64" ]]; then
        log_pass "ARM64 architecture detected (expected for Pi 5 target)."
    else
        log_warn "Non-ARM64 architecture detected ($arch). This is fine for pre-flight, not target parity."
    fi

    if [[ "$kernel" == *"rt"* || "$kernel" == *"PREEMPT_RT"* ]]; then
        log_pass "RT-flavored kernel detected: $kernel"
    else
        log_warn "Kernel string does not indicate RT. Verify PREEMPT_RT on target machine."
    fi
}

check_realtime_indicators() {
    if [[ -f /sys/kernel/realtime ]]; then
        if [[ "$(cat /sys/kernel/realtime 2>/dev/null)" == "1" ]]; then
            log_pass "Kernel reports realtime=1"
        else
            log_warn "Kernel reports realtime=0"
        fi
    else
        log_warn "/sys/kernel/realtime not present"
    fi

    if have_cmd cyclictest; then
        log_info "Running short cyclictest sample (5 seconds) ..."
        if timeout 8s cyclictest -Sp90 -i200 -D5s >"$OUT_DIR/cyclictest.txt" 2>&1; then
            log_pass "cyclictest completed (see $OUT_DIR/cyclictest.txt)"
        else
            log_warn "cyclictest did not complete cleanly (see $OUT_DIR/cyclictest.txt)"
        fi
    else
        log_warn "cyclictest not installed (package: rt-tests)"
    fi
}

check_graphics_path() {
    if have_cmd glxinfo; then
        if glxinfo -B >"$OUT_DIR/glxinfo_B.txt" 2>&1; then
            log_pass "glxinfo -B succeeded (see $OUT_DIR/glxinfo_B.txt)"
            if grep -Eqi "llvmpipe|software rasterizer" "$OUT_DIR/glxinfo_B.txt"; then
                log_warn "Software rendering detected (llvmpipe/software rasterizer)."
            else
                log_pass "No software rasterizer signature detected in glxinfo output."
            fi
        else
            log_warn "glxinfo -B failed (see $OUT_DIR/glxinfo_B.txt)"
        fi
    else
        log_warn "glxinfo not installed (package: mesa-utils)"
    fi
}

check_python_stack() {
    check_cmd python3 "Install Python 3 runtime"

    check_python_import "PySide6" "PySide6"
    check_python_import "vtk" "VTK"

    if python3 - <<'PY' >/dev/null 2>&1
from PySide6 import Qsci
print(Qsci)
PY
    then
        log_pass "PySide6.Qsci import OK"
    else
        log_warn "PySide6.Qsci import failed (PySide6/Qt6-only policy active). Python QScintilla editor path may be unavailable."
    fi
}

check_debian_packages() {
    check_pkg_installed "python3-vtk9"
    check_pkg_installed "python3-pyside6.qtwidgets"
    check_pkg_installed "python3-pyside6.qtuitools"
    check_pkg_installed "python3-pyside6.qsci"
    if dpkg-query -W -f='${Status}' "python3-pyqt5.qsci" 2>/dev/null | grep -q "install ok installed"; then
        log_warn "Package installed: python3-pyqt5.qsci (policy note: this machine is PySide6/Qt6-only)."
    else
        log_pass "PyQt5 Qsci fallback not installed (PySide6/Qt6-only policy preserved)."
    fi
    check_pkg_installed "mesa-utils"
    check_pkg_installed "linux-image-rt-amd64"
}

check_linuxcnc_cli() {
    if have_cmd linuxcnc; then
        log_pass "linuxcnc command available"
        if linuxcnc -h >"$OUT_DIR/linuxcnc_help.txt" 2>&1; then
            log_pass "linuxcnc -h succeeded"
        else
            log_warn "linuxcnc -h failed (see $OUT_DIR/linuxcnc_help.txt)"
        fi
    else
        log_fail "linuxcnc command is not available"
    fi
}

check_ini_path() {
    if [[ -n "$INI_PATH" ]]; then
        if [[ -f "$INI_PATH" ]]; then
            log_pass "INI file exists: $INI_PATH"
        else
            log_fail "INI file does not exist: $INI_PATH"
        fi
    else
        log_info "No INI supplied; skipping INI-specific checks."
    fi
}

run_linuxcnc_probe() {
    local log_file="$OUT_DIR/linuxcnc_probe.log"

    if [[ "$RUN_LINUXCNC" -ne 1 ]]; then
        log_info "--run-linuxcnc not requested; skipping launch probe."
        return
    fi

    if [[ -z "$INI_PATH" ]]; then
        log_warn "--run-linuxcnc requested but no --ini path provided."
        return
    fi

    if ! have_cmd linuxcnc; then
        log_fail "Cannot run LinuxCNC probe: linuxcnc command missing."
        return
    fi

    log_info "Running LinuxCNC probe for up to 30s ..."
    if timeout 30s linuxcnc -v -r "$INI_PATH" >"$log_file" 2>&1; then
        log_pass "LinuxCNC probe exited cleanly (see $log_file)"
    else
        local rc=$?
        if [[ $rc -eq 124 ]]; then
            log_warn "LinuxCNC probe timed out after 30s (often normal for GUI apps). See $log_file"
        elif [[ $rc -eq 137 ]]; then
            log_fail "LinuxCNC probe terminated with 137 (likely SIGKILL/OOM). See $log_file"
        else
            log_warn "LinuxCNC probe exited with code $rc. See $log_file"
        fi
    fi

    if have_cmd dmesg; then
        dmesg -T | grep -Ei "oom|killed process|segfault|drm|gpu|v3d|i915" | tail -n 80 >"$OUT_DIR/dmesg_focus.txt" || true
        if [[ -s "$OUT_DIR/dmesg_focus.txt" ]]; then
            log_warn "Kernel warnings/errors captured in $OUT_DIR/dmesg_focus.txt"
        else
            log_pass "No matching OOM/segfault/DRM/GPU entries in focused dmesg scan"
        fi
    fi
}

print_summary() {
    echo
    echo "====================="
    echo "Validation Summary"
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

    check_system_baseline
    check_realtime_indicators
    check_graphics_path
    check_python_stack
    check_debian_packages
    check_linuxcnc_cli
    check_ini_path
    run_linuxcnc_probe
    print_summary
}

main "$@"
