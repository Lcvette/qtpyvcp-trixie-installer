# Script Helpers

This folder contains helper scripts for Raspberry Pi 5 / Debian trixie preflight and runtime validation.

## Scripts

- `pi5_preflight.sh`
  - Bare-machine preflight.
  - Does not install LinuxCNC or QtPyVCP.
  - Internally runs `apt-cache policy` candidate checks and `apt-get -s install` dry-run dependency resolution checks.

- `pi5_validate.sh`
  - Runtime validation script.
  - Checks environment and dependencies.
  - Optionally launches LinuxCNC with a provided INI (`--run-linuxcnc`) for smoke testing.

## Usage

```bash
# Bare preflight (no install actions)
./scripts/pi5_preflight.sh

# Full validation with Probe Basic INI
./scripts/pi5_validate.sh \
  --ini ~/Dev/probe_basic/configs/probe_basic/probe_basic.ini \
  --run-linuxcnc
```

Both scripts write logs to `/tmp` by default and support `--out-dir`.
