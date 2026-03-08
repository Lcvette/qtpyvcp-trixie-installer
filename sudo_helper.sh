#!/bin/bash
set -euo pipefail

# Used by sudo -A via SUDO_ASKPASS to request the password graphically.
zenity --password --title="SUDO Password"
