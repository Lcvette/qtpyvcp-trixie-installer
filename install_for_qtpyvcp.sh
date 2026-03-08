#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="$(whoami)"

# Backward-compatible askpass behavior:
# if sudo_helper.sh is missing, create a temporary helper so the installer still runs standalone.
if [ -x "$SCRIPT_DIR/sudo_helper.sh" ]; then
  export SUDO_ASKPASS="$SCRIPT_DIR/sudo_helper.sh"
else
  SUDO_ASKPASS_FALLBACK="$(mktemp)"
  cat > "$SUDO_ASKPASS_FALLBACK" <<'EOF'
#!/bin/bash
if command -v zenity >/dev/null 2>&1; then
  zenity --password --title="SUDO Password"
else
  read -rsp "SUDO Password: " pass
  echo
  printf '%s\n' "$pass"
fi
EOF
  chmod 700 "$SUDO_ASKPASS_FALLBACK"
  export SUDO_ASKPASS="$SUDO_ASKPASS_FALLBACK"
  trap 'rm -f "$SUDO_ASKPASS_FALLBACK"' EXIT
fi

# pyqt5 main branch and pyside6 branch install are intentionally separate installers.
QTPYVCP_REPO="https://github.com/kcjengr/qtpyvcp.git"
PROBE_BASIC_REPO="https://github.com/kcjengr/probe_basic.git"
TARGET_BRANCH="pyside6"

printf "\n[qtpyvcp-trixie-installer] Installing Trixie/PySide6 development dependencies...\n"

sudo -A apt update
sudo -A apt install -y \
  python3-venv \
  python3-pip \
  python3-dev \
  python3-setuptools \
  python3-wheel \
  python3-six \
  python3-docopt \
  python3-qtpy \
  python3-pyudev \
  python3-psutil \
  python3-markupsafe \
  python3-opengl \
  python3-vtk9 \
  python3-pyqtgraph \
  python3-simpleeval \
  python3-jinja2 \
  python3-deepdiff \
  python3-sqlalchemy \
  python3-yaml \
  python3-distro \
  python3-serial \
  cmake \
  build-essential \
  git \
  zenity \
  qt6-base-dev \
  qt6-tools-dev-tools \
  qt6-l10n-tools \
  qml6-module-qtquick-controls \
  qml6-module-qtquick-controls2 \
  qml6-module-qtquick-shapes \
  gstreamer1.0-plugins-bad \
  libqt6multimedia6-plugins \
  pyside6-tools \
  python3-pyside6.qtcore \
  python3-pyside6.qtdbus \
  python3-pyside6.qtopengl \
  python3-pyside6.qtwidgets \
  python3-pyside6.qtmultimedia \
  python3-pyside6.qtquick

printf "\n[qtpyvcp-trixie-installer] Choose install scope...\n"
if zenity --question --text="Install qtpyvcp only, or qtpyvcp + probe_basic?" --no-wrap --ok-label="QTPYVCP" --cancel-label="BOTH"; then
  INSTALL_BOTH=0
else
  INSTALL_BOTH=1
fi

mkdir -p "$HOME/dev"
cd "$HOME/dev"

clone_or_update_branch() {
  local repo_url="$1"
  local dir_name="$2"

  if [ ! -d "$dir_name/.git" ]; then
    git clone -b "$TARGET_BRANCH" --single-branch "$repo_url" "$dir_name"
  else
    (cd "$dir_name" && git fetch origin && git checkout "$TARGET_BRANCH" && git pull --ff-only origin "$TARGET_BRANCH")
  fi
}

clone_or_update_branch "$QTPYVCP_REPO" "qtpyvcp"
if [ "$INSTALL_BOTH" -eq 1 ]; then
  clone_or_update_branch "$PROBE_BASIC_REPO" "probe_basic"
fi

if [ ! -d "$HOME/dev/venv" ]; then
  python3 -m venv --system-site-packages "$HOME/dev/venv"
fi

# shellcheck disable=SC1091
source "$HOME/dev/venv/bin/activate"

pip install --upgrade pip
pip install hiyapyco

printf "\n[qtpyvcp-trixie-installer] Installing qtpyvcp editable...\n"
cd "$HOME/dev/qtpyvcp"
pip install -e .
qcompile .

# Always clean stale native modules before qnative to avoid cross-arch leftovers in reused dev trees.
find src/qtpyvcp/native -type f \( -name "*_backplot_cpp*.so" -o -name "*gcodeeditorplugin*.so" \) -delete || true
qnative --build-root /tmp/qnative-build

cp scripts/.xsessionrc "$HOME/"
cp -r "$HOME/dev/qtpyvcp/linuxcnc" "$HOME/" || true

if [ "$INSTALL_BOTH" -eq 1 ]; then
  printf "\n[qtpyvcp-trixie-installer] Installing probe_basic editable...\n"
  cd "$HOME/dev/probe_basic"
  pip install -e .
  qcompile .

  mkdir -p "$HOME/linuxcnc/configs"
  cp -r "$HOME/dev/probe_basic/configs/probe_basic" "$HOME/linuxcnc/configs/" || true

  test -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" && source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
  DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  mkdir -p "$DESKTOP_DIR"

  cp "$HOME/dev/probe_basic/dev_launchers/Designer for PB Lathe.desktop" "$DESKTOP_DIR/Designer for PB Lathe.desktop"
  cp "$HOME/dev/probe_basic/dev_launchers/Designer for PB Mill.desktop" "$DESKTOP_DIR/Designer for PB Mill.desktop"
  cp "$HOME/dev/probe_basic/dev_launchers/Probe Basic Mill.desktop" "$DESKTOP_DIR/Probe Basic Mill.desktop"
  cp "$HOME/dev/probe_basic/dev_launchers/Probe Basic Lathe.desktop" "$DESKTOP_DIR/Probe Basic Lathe.desktop"
  cp "$HOME/dev/probe_basic/dev_launchers/Probe Basic ATC Mill.desktop" "$DESKTOP_DIR/Probe Basic ATC Mill.desktop"
  cp "$HOME/dev/probe_basic/dev_launchers/Probe Basic ATC Mill Metric.desktop" "$DESKTOP_DIR/Probe Basic ATC Mill Metric.desktop"
  cp "$HOME/dev/probe_basic/dev_launchers/Probe Basic Rack ATC Mill.desktop" "$DESKTOP_DIR/Probe Basic Rack ATC Mill.desktop"

  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Designer for PB Lathe.desktop"
  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Designer for PB Mill.desktop"
  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Probe Basic Mill.desktop"
  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Probe Basic Lathe.desktop"
  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Probe Basic ATC Mill.desktop"
  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Probe Basic ATC Mill Metric.desktop"
  sed -i "s/username/$USERNAME/g" "$DESKTOP_DIR/Probe Basic Rack ATC Mill.desktop"

  mkdir -p "$HOME/.local/share/icons" "$HOME/.local/share/fonts"
  cp "$HOME/dev/probe_basic/dev_launchers/probe_basic_icon.png" "$HOME/.local/share/icons/probe_basic_mill.png"
  cp "$HOME/dev/probe_basic/dev_launchers/probe_basic_icon_lathe.png" "$HOME/.local/share/icons/probe_basic_lathe.png"
  cp "$HOME/dev/probe_basic/dev_launchers/qtpyvcp2.png" "$HOME/.local/share/icons/qtpyvcp.png"
  cp "$HOME/dev/probe_basic/fonts/BebasKai.ttf" "$HOME/.local/share/fonts/BebasKai.ttf" || true
fi

if ! grep -q 'source ~/dev/venv/bin/activate' "$HOME/.bashrc"; then
  echo 'source ~/dev/venv/bin/activate' >> "$HOME/.bashrc"
fi

printf "\n[qtpyvcp-trixie-installer] Install complete.\n"
if zenity --question --text="Do you want to reboot now?"; then
  xfce4-session-logout --reboot
fi
