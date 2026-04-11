#!/bin/bash

export PATH=$HOME/.local/bin:$PATH
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SUDO_ASKPASS="$SCRIPT_DIR/sudo_helper.sh"
USERNAME=$(whoami)

# Resolve workspace path case consistently across machines.
if [ -d "$HOME/Dev" ] && [ -d "$HOME/dev" ]; then
    if [ -d "$HOME/Dev/venv" ]; then
        DEV_DIR="$HOME/Dev"
    elif [ -d "$HOME/dev/venv" ]; then
        DEV_DIR="$HOME/dev"
    else
        DEV_DIR="$HOME/Dev"
    fi
elif [ -d "$HOME/Dev" ]; then
    DEV_DIR="$HOME/Dev"
elif [ -d "$HOME/dev" ]; then
    DEV_DIR="$HOME/dev"
else
    DEV_DIR="$HOME/Dev"
fi

VENV_PATH="$DEV_DIR/venv"

disable_linuxcnc_source_repo () {
    local list_file="/etc/apt/sources.list.d/linuxcnc.list"

    # Keep LinuxCNC binary-only repo to avoid source index warning noise.
    if [ -f "$list_file" ]
    then
        sudo -A sed -i '/linuxcnc\.org/ s/^[[:space:]]*deb-src[[:space:]]\+/# deb-src /' "$list_file" || true
    fi
}

check_conflicting_system_installs () {
    local -a conflicting_packages=()
    local package_list
    local prompt_remove=1

    package_list=$(dpkg-query -W -f='${Package}\t${Status}\n' '*qtpyvcp*' '*probe-basic*' '*probebasic*' 2>/dev/null | awk '$2 == "install" && $3 == "ok" && $4 == "installed" {print $1}')

    if [ -n "$package_list" ]
    then
        while IFS= read -r pkg
        do
            [ -n "$pkg" ] && conflicting_packages+=("$pkg")
        done <<< "$package_list"
    fi

    if [ ${#conflicting_packages[@]} -eq 0 ]
    then
        return 0
    fi

    local package_text
    package_text=$(printf '%s\n' "${conflicting_packages[@]}")

    echo "Detected system-wide qtpyvcp/Probe Basic packages that can conflict with the development install:"
    echo "$package_text"

    local prompt_message
    prompt_message="System-wide qtpyvcp or Probe Basic packages were detected and can conflict with this development installer.\n\nRemove these packages now and continue?\n\nDetected packages:\n$package_text"

    if command -v zenity >/dev/null 2>&1
    then
        if zenity --question --title="Conflicting Packages Detected" --no-wrap --ok-label="REMOVE AND CONTINUE" --cancel-label="ABORT INSTALLER" --text="$prompt_message"
        then
            prompt_remove=0
        fi
    else
        echo
        echo "This installer requires removing the above apt/dpkg packages before continuing."
        read -r -p "Remove detected packages now? [Y/n]: " REPLY
        case "$REPLY" in
            n|N) prompt_remove=1 ;;
            *) prompt_remove=0 ;;
        esac
    fi

    if [ $prompt_remove -ne 0 ]
    then
        echo "Installer aborted. Remove system-wide qtpyvcp/Probe Basic packages and rerun this script."
        exit 1
    fi

    echo "Removing conflicting packages..."
    if ! sudo -A apt purge -y "${conflicting_packages[@]}"
    then
        echo "Failed to remove one or more conflicting packages."
        echo "Please remove them manually, then rerun this installer."
        exit 1
    fi

    sudo -A apt autoremove -y || true
}

echo -e "\e[1;34m                                                                               \e[0m"
echo -e "\e[1;34m               ___  ____ ____ ___  ____    ___  ____ ____ _ ____               \e[0m"
echo -e "\e[1;34m               |__] |__/ |  | |__] |___    |__] |__| [__  | |                  \e[0m"
echo -e "\e[1;34m               |    |  \ |__| |__] |___    |__] |  | ___] | |___               \e[0m"
echo -e "\e[1;34m                                                                               \e[0m"
echo -e "\e[1;34m               ___  ____ _    _   _ _  _ ____ ___ ____ _    _                  \e[0m"
echo -e "\e[1;34m               |  | |__   \  /    | |\ | [__   |  |__| |    |                  \e[0m"
echo -e "\e[1;34m               |__| |___   \/     | | \| ___]  |  |  | |___ |___               \e[0m"
echo -e "\e[1;34m                                                                               \e[0m"
echo -e "\e[1;34m        https://github.com/kcjengr/probe_basic   By @Lcvette  2026             \e[0m"
echo -e "\e[1;34m                                                                               \e[0m"

# Bootstrap required tools before askpass mode.
# If zenity is missing, sudo -A cannot show the password dialog yet.
if ! command -v zenity >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1
then
    echo -e "\e[1;34mInstalling required bootstrap packages (zenity, git)...\e[0m"
    sudo apt update
    sudo apt install -y zenity git
fi

check_conflicting_system_installs

echo -e "\e[1;34mDebian Trixie dependencies install started\e[0m"

disable_linuxcnc_source_repo
sudo -A apt update
# Keep this list in sync with the PySide6/Qt6 runtime needs observed in Probe Basic + QtPyVCP.
sudo -A apt install -y python3-venv python3-pip python3-pybind11 python3-hiyapyco python3-dev python3-setuptools python3-wheel python3-six python3-docopt python3-qtpy python3-pyudev python3-psutil python3-markupsafe python3-opengl python3-vtk9 python3-pyqtgraph python3-simpleeval python3-jinja2 python3-deepdiff python3-sqlalchemy python3-yaml python3-distro python3-serial pybind11-dev cmake build-essential git zenity curl qt6-base-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-shapes qml6-module-qtmultimedia gstreamer1.0-plugins-bad libqt6multimedia6 pyside6-tools python3-pyside6.qtcore python3-pyside6.qtdbus python3-pyside6.qtdesigner python3-pyside6.qtopengl python3-pyside6.qtwidgets python3-pyside6.qtmultimedia python3-pyside6.qtquick python3-pyside6.qtuitools mesa-utils rt-tests
SUDO_ERROR=$?

if [ $SUDO_ERROR -eq 1 ]
then
    exit 1
fi

if ! command -v linuxcnc >/dev/null 2>&1 && ! dpkg -s linuxcnc-uspace >/dev/null 2>&1 && ! dpkg -s linuxcnc >/dev/null 2>&1
then
    echo "LinuxCNC is required and does not appear to be installed system-wide."

    INSTALL_LINUXCNC=1
    if command -v zenity >/dev/null 2>&1
    then
        if zenity --question --text="LinuxCNC is required. Install linuxcnc-uspace now?" --no-wrap --ok-label="INSTALL" --cancel-label="CANCEL"
        then
            INSTALL_LINUXCNC=0
        fi
    else
        read -r -p "Install linuxcnc-uspace now? [Y/n]: " REPLY
        case "$REPLY" in
            n|N) INSTALL_LINUXCNC=1 ;;
            *) INSTALL_LINUXCNC=0 ;;
        esac
    fi

    if [ $INSTALL_LINUXCNC -eq 0 ]
    then
        LINUXCNC_INSTALLER=$(mktemp /tmp/linuxcnc-install.XXXXXX.sh)
        if ! curl -fsSL https://www.linuxcnc.org/linuxcnc-install.sh -o "$LINUXCNC_INSTALLER" || ! chmod +x "$LINUXCNC_INSTALLER" || ! sudo -A "$LINUXCNC_INSTALLER"
        then
            rm -f "$LINUXCNC_INSTALLER"
            echo "Unable to install linuxcnc-uspace automatically."
            echo "Install LinuxCNC manually, then rerun this installer."
            exit 1
        fi
        rm -f "$LINUXCNC_INSTALLER"
        disable_linuxcnc_source_repo
    else
        echo "LinuxCNC installation was skipped."
        echo "Install LinuxCNC system-wide, then rerun this installer."
        exit 1
    fi
fi

ensure_dev_venv () {
    if [ ! -d "$VENV_PATH" ]
    then
        python3 -m venv --system-site-packages "$VENV_PATH"
        VENV_ERROR=$?

        if [ $VENV_ERROR -ne 0 ]
        then
            PY_MAJ_MIN=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
            echo -e "\e[1;34mInstalling missing venv package for python ${PY_MAJ_MIN}...\e[0m"

            if ! sudo -A apt install -y "python${PY_MAJ_MIN}-venv" python3-venv python3-pip; then
                sudo -A apt install -y python3-venv python3-pip
            fi

            python3 -m venv --system-site-packages "$VENV_PATH"
        fi
    fi

    if [ ! -f "$VENV_PATH/bin/activate" ]
    then
        echo "Virtual environment setup failed: $VENV_PATH/bin/activate not found"
        exit 1
    fi

    source "$VENV_PATH/bin/activate"

    if ! command -v pip >/dev/null 2>&1
    then
        python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
    fi

    if ! command -v pip >/dev/null 2>&1
    then
        echo "pip is still unavailable in $VENV_PATH after setup"
        exit 1
    fi
}

sync_repo_full_tree () {
    local repo_dir="$1"
    local repo_url="$2"
    local repo_branch="$3"

    if [ ! -d "$repo_dir/.git" ]
    then
        # Clone full repository tree/history while still checking out the requested branch.
        git clone -b "$repo_branch" "$repo_url" "$repo_dir"
    else
        (
            cd "$repo_dir" || exit 1
            git remote set-url origin "$repo_url"
            git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
            git remote set-branches origin '*'
            git fetch --all --tags --prune

            if [ -f .git/shallow ]
            then
                git fetch --unshallow --tags origin
            fi

            git checkout "$repo_branch"
            git pull --ff-only origin "$repo_branch"
        )
    fi
}

zenity --question --text="Install qtpyvcp or qtpyvcp and probe basic" --no-wrap --ok-label="QTPYVCP" --cancel-label="BOTH"

BOTH=$?

if [ $BOTH -eq 1 ]
then
    echo -e "\e[1;34mQtPyVCP and Probe Basic install started\e[0m"

    mkdir -p "$DEV_DIR"
    cd "$DEV_DIR"

    sync_repo_full_tree "$DEV_DIR/qtpyvcp" "https://github.com/kcjengr/qtpyvcp.git" "pyside6"

    sync_repo_full_tree "$DEV_DIR/probe_basic" "https://github.com/kcjengr/probe_basic.git" "pyside6"

    ensure_dev_venv

    if ! python3 -c 'import hiyapyco' >/dev/null 2>&1
    then
        pip install hiyapyco
    fi

    cd qtpyvcp
    pip install -e .

    if ! command -v qcompile >/dev/null 2>&1 || ! command -v qnative >/dev/null 2>&1
    then
        echo "qcompile/qnative not found after qtpyvcp install"
        exit 1
    fi

    qcompile .
    find src/qtpyvcp/native -type f \( -name "*_backplot_cpp*.so" -o -name "*gcodeeditorplugin*.so" \) -delete || true
    rm -rf /tmp/qnative-build
    qnative --build-root /tmp/qnative-build
    cp scripts/.xsessionrc ~/
    cp -r "$DEV_DIR/qtpyvcp/linuxcnc" ~/ || true

    cd ../probe_basic
    pip install -e .
    qcompile .

    mkdir -p ~/linuxcnc/configs
    cp -r "$DEV_DIR/probe_basic/configs/probe_basic/" ~/linuxcnc/configs/ || true

    test -f ${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs && source ${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs

    cp "$DEV_DIR/probe_basic/dev_launchers/Designer for PB Lathe.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer for PB Lathe.desktop"
    cp "$DEV_DIR/probe_basic/dev_launchers/Designer for PB Mill.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer for PB Mill.desktop"
    cp "$DEV_DIR/probe_basic/dev_launchers/Probe Basic Mill.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic Mill.desktop"
    cp "$DEV_DIR/probe_basic/dev_launchers/Probe Basic Lathe.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic Lathe.desktop"
    cp "$DEV_DIR/probe_basic/dev_launchers/Probe Basic ATC Mill.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic ATC Mill.desktop"
    cp "$DEV_DIR/probe_basic/dev_launchers/Probe Basic ATC Mill Metric.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic ATC Mill Metric.desktop"
    cp "$DEV_DIR/probe_basic/dev_launchers/Probe Basic Rack ATC Mill.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic Rack ATC Mill.desktop"

    for launcher in \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer for PB Lathe.desktop" \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer for PB Mill.desktop" \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic Mill.desktop" \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic Lathe.desktop" \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic ATC Mill.desktop" \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic ATC Mill Metric.desktop" \
        "${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe Basic Rack ATC Mill.desktop"
    do
        [ -f "$launcher" ] || continue
        # Replace explicit placeholder tokens and any hardcoded /home/<user>/(dev|Dev) paths.
        sed -E -i \
            -e "s#username#$USERNAME#g" \
            -e "s#/home/[^/]+/[dD]ev#$DEV_DIR#g" \
            "$launcher"
    done

    mkdir -p /home/$USERNAME/.local/share/icons/
    mkdir -p /home/$USERNAME/.local/share/fonts/

    cp "$DEV_DIR/probe_basic/dev_launchers/probe_basic_icon.png" "/home/$USERNAME/.local/share/icons/probe_basic_mill.png"
    cp "$DEV_DIR/probe_basic/dev_launchers/probe_basic_icon_lathe.png" "/home/$USERNAME/.local/share/icons/probe_basic_lathe.png"
    cp "$DEV_DIR/probe_basic/dev_launchers/qtpyvcp2.png" "/home/$USERNAME/.local/share/icons/qtpyvcp.png"
    cp "$DEV_DIR/probe_basic/fonts/ProbeBasicBebasMono.ttf" "/home/$USERNAME/.local/share/fonts/ProbeBasicBebasMono.ttf" || true
    cp "$DEV_DIR/probe_basic/fonts/OFL-1.1.txt" "/home/$USERNAME/.local/share/fonts/ProbeBasicBebasMono-OFL-1.1.txt" || true
    cp "$DEV_DIR/probe_basic/fonts/ProbeBasicBebasMono-LICENSE.txt" "/home/$USERNAME/.local/share/fonts/ProbeBasicBebasMono-LICENSE.txt" || true
    cp "$DEV_DIR/probe_basic/fonts/ProbeBasicBebasMono-MODIFICATIONS.txt" "/home/$USERNAME/.local/share/fonts/ProbeBasicBebasMono-MODIFICATIONS.txt" || true

    if ! grep -q "source $VENV_PATH/bin/activate" ~/.bashrc; then
        echo "source $VENV_PATH/bin/activate" >> ~/.bashrc
    fi

else
    echo -e "\e[1;34mQtPyVCP install started\e[0m"
    mkdir -p "$DEV_DIR"
    cd "$DEV_DIR"

    sync_repo_full_tree "$DEV_DIR/qtpyvcp" "https://github.com/kcjengr/qtpyvcp.git" "pyside6"

    ensure_dev_venv

    if ! python3 -c 'import hiyapyco' >/dev/null 2>&1
    then
        pip install hiyapyco
    fi

    cd qtpyvcp
    pip install -e .

    if ! command -v qcompile >/dev/null 2>&1 || ! command -v qnative >/dev/null 2>&1
    then
        echo "qcompile/qnative not found after qtpyvcp install"
        exit 1
    fi

    qcompile .
    find src/qtpyvcp/native -type f \( -name "*_backplot_cpp*.so" -o -name "*gcodeeditorplugin*.so" \) -delete || true
    rm -rf /tmp/qnative-build
    qnative --build-root /tmp/qnative-build
    cp scripts/.xsessionrc ~/

    if ! grep -q "source $VENV_PATH/bin/activate" ~/.bashrc; then
        echo "source $VENV_PATH/bin/activate" >> ~/.bashrc
    fi
fi

if zenity --question --text="Do you want to reboot the system?"; then
    xfce4-session-logout --reboot
else
    exit 0
fi