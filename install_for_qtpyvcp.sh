#!/bin/bash

export PATH=$HOME/.local/bin:$PATH
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SUDO_ASKPASS="$SCRIPT_DIR/sudo_helper.sh"
USERNAME=$(whoami)

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

echo -e "\e[1;34mDebian Trixie dependencies install started\e[0m"

sudo -A apt update
sudo -A apt install -y python3-venv python3-pip python3-dev python3-setuptools python3-wheel python3-six python3-docopt python3-qtpy python3-pyudev python3-psutil python3-markupsafe python3-opengl python3-vtk9 python3-pyqtgraph python3-simpleeval python3-jinja2 python3-deepdiff python3-sqlalchemy python3-yaml python3-distro python3-serial cmake build-essential git zenity qt6-base-dev qt6-tools-dev-tools qt6-l10n-tools qml6-module-qtquick-controls qml6-module-qtquick-shapes qml6-module-qtmultimedia gstreamer1.0-plugins-bad libqt6multimedia6 pyside6-tools python3-pyside6.qtcore python3-pyside6.qtdbus python3-pyside6.qtopengl python3-pyside6.qtwidgets python3-pyside6.qtmultimedia python3-pyside6.qtquick
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
        sudo -A apt update
        if ! sudo -A apt install -y linuxcnc-uspace
        then
            echo "Unable to install linuxcnc-uspace automatically."
            echo "Install LinuxCNC manually, then rerun this installer."
            exit 1
        fi
    else
        echo "LinuxCNC installation was skipped."
        echo "Install LinuxCNC system-wide, then rerun this installer."
        exit 1
    fi
fi

ensure_dev_venv () {
    if [ ! -d ~/dev/venv ]
    then
        python3 -m venv --system-site-packages ~/dev/venv
        VENV_ERROR=$?

        if [ $VENV_ERROR -ne 0 ]
        then
            PY_MAJ_MIN=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
            echo -e "\e[1;34mInstalling missing venv package for python ${PY_MAJ_MIN}...\e[0m"

            if ! sudo -A apt install -y "python${PY_MAJ_MIN}-venv" python3-venv python3-pip; then
                sudo -A apt install -y python3-venv python3-pip
            fi

            python3 -m venv --system-site-packages ~/dev/venv
        fi
    fi

    if [ ! -f ~/dev/venv/bin/activate ]
    then
        echo "Virtual environment setup failed: ~/dev/venv/bin/activate not found"
        exit 1
    fi

    source ~/dev/venv/bin/activate

    if ! command -v pip >/dev/null 2>&1
    then
        python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
    fi

    if ! command -v pip >/dev/null 2>&1
    then
        echo "pip is still unavailable in ~/dev/venv after setup"
        exit 1
    fi
}

zenity --question --text="Install qtpyvcp or qtpyvcp and probe basic" --no-wrap --ok-label="QTPYVCP" --cancel-label="BOTH"

BOTH=$?

if [ $BOTH -eq 1 ]
then
    echo -e "\e[1;34mQtPyVCP and Probe Basic install started\e[0m"

    mkdir -p ~/dev
    cd ~/dev

    if [ ! -d ~/dev/qtpyvcp/.git ]
    then
        git clone -b pyside6 --single-branch https://github.com/kcjengr/qtpyvcp.git
    else
        cd ~/dev/qtpyvcp
        git fetch origin
        git checkout pyside6
        git pull --ff-only origin pyside6
        cd ~/dev
    fi

    if [ ! -d ~/dev/probe_basic/.git ]
    then
        git clone -b pyside6 --single-branch https://github.com/kcjengr/probe_basic.git
    else
        cd ~/dev/probe_basic
        git fetch origin
        git checkout pyside6
        git pull --ff-only origin pyside6
        cd ~/dev
    fi

    ensure_dev_venv

    pip install hiyapyco

    cd qtpyvcp
    pip install -e .

    if ! command -v qcompile >/dev/null 2>&1 || ! command -v qnative >/dev/null 2>&1
    then
        echo "qcompile/qnative not found after qtpyvcp install"
        exit 1
    fi

    qcompile .
    find src/qtpyvcp/native -type f \( -name "*_backplot_cpp*.so" -o -name "*gcodeeditorplugin*.so" \) -delete || true
    qnative --build-root /tmp/qnative-build
    cp scripts/.xsessionrc ~/
    cp -r ~/dev/qtpyvcp/linuxcnc ~/ || true

    cd ../probe_basic
    pip install -e .
    qcompile .

    mkdir -p ~/linuxcnc/configs
    cp -r ~/dev/probe_basic/configs/probe_basic/ ~/linuxcnc/configs/ || true

    test -f ${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs && source ${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs

    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Designer\ for\ PB\ Lathe.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer\ for\ PB\ Lathe.desktop
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Designer\ for\ PB\ Mill.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer\ for\ PB\ Mill.desktop
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Probe\ Basic\ Mill.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ Mill.desktop
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Probe\ Basic\ Lathe.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ Lathe.desktop
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Probe\ Basic\ ATC\ Mill.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ ATC\ Mill.desktop
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Probe\ Basic\ ATC\ Mill\ Metric.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ ATC\ Mill\ Metric.desktop
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/Probe\ Basic\ Rack\ ATC\ Mill.desktop ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ Rack\ ATC\ Mill.desktop

    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer\ for\ PB\ Lathe.desktop
    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Designer\ for\ PB\ Mill.desktop
    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ Mill.desktop
    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ Lathe.desktop
    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ ATC\ Mill.desktop
    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ ATC\ Mill\ Metric.desktop
    sed -i "s/username/$USERNAME/g" ${XDG_DESKTOP_DIR:-$HOME/Desktop}/Probe\ Basic\ Rack\ ATC\ Mill.desktop

    mkdir -p /home/$USERNAME/.local/share/icons/
    mkdir -p /home/$USERNAME/.local/share/fonts/

    cp /home/$USERNAME/dev/probe_basic/dev_launchers/probe_basic_icon.png /home/$USERNAME/.local/share/icons/probe_basic_mill.png
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/probe_basic_icon_lathe.png /home/$USERNAME/.local/share/icons/probe_basic_lathe.png
    cp /home/$USERNAME/dev/probe_basic/dev_launchers/qtpyvcp2.png /home/$USERNAME/.local/share/icons/qtpyvcp.png
    cp /home/$USERNAME/dev/probe_basic/fonts/BebasKai.ttf /home/$USERNAME/.local/share/fonts/BebasKai.ttf || true

    if ! grep -q 'source ~/dev/venv/bin/activate' ~/.bashrc; then
        echo "source ~/dev/venv/bin/activate" >> ~/.bashrc
    fi

else
    echo -e "\e[1;34mQtPyVCP install started\e[0m"
    mkdir -p ~/dev
    cd ~/dev

    if [ ! -d ~/dev/qtpyvcp/.git ]
    then
        git clone -b pyside6 --single-branch https://github.com/kcjengr/qtpyvcp.git
    else
        cd ~/dev/qtpyvcp
        git fetch origin
        git checkout pyside6
        git pull --ff-only origin pyside6
        cd ~/dev
    fi

    ensure_dev_venv

    pip install hiyapyco

    cd qtpyvcp
    pip install -e .

    if ! command -v qcompile >/dev/null 2>&1 || ! command -v qnative >/dev/null 2>&1
    then
        echo "qcompile/qnative not found after qtpyvcp install"
        exit 1
    fi

    qcompile .
    find src/qtpyvcp/native -type f \( -name "*_backplot_cpp*.so" -o -name "*gcodeeditorplugin*.so" \) -delete || true
    qnative --build-root /tmp/qnative-build
    cp scripts/.xsessionrc ~/

    if ! grep -q 'source ~/dev/venv/bin/activate' ~/.bashrc; then
        echo "source ~/dev/venv/bin/activate" >> ~/.bashrc
    fi
fi

if zenity --question --text="Do you want to reboot the system?"; then
    xfce4-session-logout --reboot
else
    exit 0
fi
