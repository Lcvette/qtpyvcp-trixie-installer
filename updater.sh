#!/bin/bash
set -euo pipefail

TARGET_BRANCH="pyside6"
DEV_DIR="$HOME/dev"
VENV_PATH="$DEV_DIR/venv"
QTPYVCP_DIR="$DEV_DIR/qtpyvcp"
PROBE_BASIC_DIR="$DEV_DIR/probe_basic"

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

echo "[qtpyvcp-trixie-installer] Update complete."
