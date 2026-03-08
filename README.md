# qtpyvcp-trixie-installer

Developer installer and updater for QtPyVCP on Debian Trixie using the `pyside6` branches.

This repository is intended for contributors and local development, not end-user production deployment.

## What It Sets Up

- System-wide LinuxCNC prerequisite verification (with optional auto-install prompt for `linuxcnc-uspace` if missing)
- A development virtual environment at `~/dev/venv`
- `qtpyvcp` cloned to `~/dev/qtpyvcp` on branch `pyside6`
- Optional `probe_basic` cloned to `~/dev/probe_basic` on branch `pyside6`
- Editable Python installs (`pip install -e .`)
- Compiled Qt resources (`qcompile .`)
- Native module build refresh (`qnative --build-root /tmp/qnative-build`)

## Scripts

- `install_for_qtpyvcp.sh`
	- Installs dependencies
	- Bootstraps `zenity` and `git` if they are missing
	- Requires LinuxCNC system-wide (offers to install `linuxcnc-uspace` when missing)
	- Clones/updates repos on the `pyside6` branch
	- Creates and activates `~/dev/venv` (with auto-recovery for missing `pythonX.Y-venv`)
	- Installs and compiles QtPyVCP (and optionally Probe Basic)

- `updater.sh`
	- Updates existing local repos to latest `pyside6`
	- Re-runs compile steps
	- Rebuilds native modules for QtPyVCP

- `sudo_helper.sh`
	- Askpass helper used by `sudo -A` for GUI password prompt via Zenity

## Quick Start

```bash
chmod +x install_for_qtpyvcp.sh updater.sh sudo_helper.sh
./install_for_qtpyvcp.sh
```

After initial setup:

```bash
./updater.sh
```

## Notes

- Branch pinning is intentional: both repos are kept on `pyside6`.
- If you switch machines/architectures or reuse old trees, rerun `./updater.sh` to refresh native artifacts.
- If LinuxCNC install is cancelled or fails, the installer exits so setup does not continue in a broken state.
