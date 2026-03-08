# qtpyvcp-trixie-installer

## General installation approach

This installer script sets up QtPyVCP and optional Probe Basic on Debian Trixie using the `pyside6` branches.
It installs into a virtual environment at `~/Dev/venv` and keeps sources in `~/Dev`.

## Installation steps

**1. Ensure LinuxCNC is installed system-wide.**

The installer checks this and can offer to install `linuxcnc-uspace` if missing.
If LinuxCNC installation is skipped or fails, the installer exits.

**2. Create Dev directory and Clone the installer repo.**

```bash
cd ~
mkdir -p Dev
cd Dev
git clone https://github.com/Lcvette/qtpyvcp-trixie-installer.git
cd qtpyvcp-trixie-installer
```

**3. Run the installer script.**

```bash
./install_for_qtpyvcp.sh
```

What the installer does:
- Installs required dependencies for Trixie/PySide6
- Bootstraps `git` and `zenity` if needed
- Clones or updates `qtpyvcp` and optional `probe_basic` on `pyside6`
- Creates `~/Dev/venv` with recovery for missing `pythonX.Y-venv`
- Installs editable packages and runs `qcompile` and `qnative`

## Updating

From the installer repo directory:

```bash
./updater.sh
```

This updates repositories, recompiles resources, and refreshes native modules.

## Uninstall

This is a local dev-style install. Remove the `~/Dev` workspace to remove the environment and cloned sources.

## Notes

- Branch pinning is intentional: `qtpyvcp` and `probe_basic` use `pyside6`.
- If you switch machines/architectures or reuse old trees, rerun `./updater.sh`.
- Scripts expected in this repo: `install_for_qtpyvcp.sh`, `updater.sh`, `sudo_helper.sh`.
