#!/bin/bash
set -euo pipefail

TARGET_BRANCH="pyside6"
DEV_DIR="$HOME/Dev"
VENV_PATH="$DEV_DIR/venv"
QTPYVCP_DIR="$DEV_DIR/qtpyvcp"
PROBE_BASIC_DIR="$DEV_DIR/probe_basic"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SUDO_ASKPASS="$SCRIPT_DIR/sudo_helper.sh"

if [ ! -d "$VENV_PATH" ]; then
  echo "[qtpyvcp-trixie-installer] Missing virtualenv at $VENV_PATH"
  echo "Run ./install_for_qtpyvcp.sh first."
  exit 1
fi

# shellcheck disable=SC1091
source "$VENV_PATH/bin/activate"

update_repo_branch() {
  local repo_dir="$1"

  if [ ! -d "$repo_dir/.git" ]; then
    echo "[qtpyvcp-trixie-installer] Skipping missing repo: $repo_dir"
    return 0
  fi

  echo "[qtpyvcp-trixie-installer] Updating $(basename "$repo_dir") on branch $TARGET_BRANCH"
  cd "$repo_dir"
  git fetch origin
  git checkout "$TARGET_BRANCH"
  git pull --ff-only origin "$TARGET_BRANCH"
}

maybe_update_linuxcnc() {
  local update_linuxcnc=1
  local linuxcnc_installer

  if command -v zenity >/dev/null 2>&1; then
    if zenity --question --text="Check and update LinuxCNC from linuxcnc.org repository now?" --no-wrap --ok-label="UPDATE" --cancel-label="SKIP"; then
      update_linuxcnc=0
    fi
  else
    read -r -p "Check and update LinuxCNC now? [Y/n]: " REPLY
    case "$REPLY" in
      n|N) update_linuxcnc=1 ;;
      *) update_linuxcnc=0 ;;
    esac
  fi

  if [ $update_linuxcnc -eq 0 ]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "[qtpyvcp-trixie-installer] curl is required to update LinuxCNC"
      return 1
    fi

    linuxcnc_installer=$(mktemp /tmp/linuxcnc-install.XXXXXX.sh)
    if ! curl -fsSL https://www.linuxcnc.org/linuxcnc-install.sh -o "$linuxcnc_installer" || ! chmod +x "$linuxcnc_installer" || ! sudo -A "$linuxcnc_installer"; then
      rm -f "$linuxcnc_installer"
      echo "[qtpyvcp-trixie-installer] LinuxCNC update failed"
      return 1
    fi
    rm -f "$linuxcnc_installer"
  fi
}

maybe_sync_deps() {
  local missing_pkgs=()
  local sync_deps=1
  local pkg

  # Minimal runtime and diagnostics packages observed as needed in field validation.
  for pkg in python3-pyside6.qtuitools python3-pyside6.qtdesigner qml6-module-qtquick-layouts mesa-utils rt-tests; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing_pkgs+=("$pkg")
    fi
  done

  if [ ${#missing_pkgs[@]} -eq 0 ]; then
    echo "[qtpyvcp-trixie-installer] Dependency baseline already satisfied."
    return 0
  fi

  echo "[qtpyvcp-trixie-installer] Missing dependency packages: ${missing_pkgs[*]}"

  if command -v zenity >/dev/null 2>&1; then
    if zenity --question --text="Install missing dependency packages now?\n\n${missing_pkgs[*]}" --no-wrap --ok-label="INSTALL" --cancel-label="SKIP"; then
      sync_deps=0
    fi
  else
    read -r -p "Install missing dependency packages now? [Y/n]: " REPLY
    case "$REPLY" in
      n|N) sync_deps=1 ;;
      *) sync_deps=0 ;;
    esac
  fi

  if [ $sync_deps -eq 0 ]; then
    sudo -A apt update
    sudo -A apt install -y "${missing_pkgs[@]}"
  else
    echo "[qtpyvcp-trixie-installer] Skipping dependency sync."
  fi
}

if [ ! -d "$QTPYVCP_DIR/.git" ]; then
  echo "[qtpyvcp-trixie-installer] Missing qtpyvcp repo at $QTPYVCP_DIR"
  echo "Run ./install_for_qtpyvcp.sh first."
  exit 1
fi

update_repo_branch "$QTPYVCP_DIR"

cd "$QTPYVCP_DIR"
qcompile .

# Remove stale native artifacts before rebuilding to avoid mixed-arch leftovers.
find src/qtpyvcp/native -type f \( -name "*_backplot_cpp*.so" -o -name "*gcodeeditorplugin*.so" \) -delete || true
qnative --build-root /tmp/qnative-build

if [ -d "$PROBE_BASIC_DIR/.git" ]; then
  update_repo_branch "$PROBE_BASIC_DIR"
  cd "$PROBE_BASIC_DIR"
  qcompile .
fi

maybe_sync_deps
maybe_update_linuxcnc

echo "[qtpyvcp-trixie-installer] Update complete."
