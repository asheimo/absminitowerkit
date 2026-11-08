#!/bin/bash
# patch_shutdown_fix.sh
#
# Live-patches the two installed minitower service files to fix the issue
# where the OLED screen and LED strip stay on through shutdown.
#
# Root cause: DefaultDependencies=no makes systemd skip the standard
# shutdown ordering, so the services never receive SIGTERM during poweroff.
#
# This script:
#   - Replaces DefaultDependencies=no with After=multi-user.target
#   - Adds KillSignal=SIGTERM and TimeoutStopSec=5 so cleanup actually runs
#   - Reloads systemd
#
# Run as root. Test by issuing `sudo systemctl stop minitower_oled` first --
# the OLED should blank within ~1 second. Then test a real shutdown.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi

MOODLIGHT=/etc/systemd/system/minitower_moodlight.service
OLED=/etc/systemd/system/minitower_oled.service

for f in "$MOODLIGHT" "$OLED"; do
    if [ ! -f "$f" ]; then
        echo "Missing: $f -- is the kit installed?"
        exit 1
    fi
    cp "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"
done

# Patch: swap DefaultDependencies=no -> After=multi-user.target
sed -i 's/^DefaultDependencies=no$/After=multi-user.target/' "$MOODLIGHT" "$OLED"

# Patch: add KillSignal + TimeoutStopSec after Type=simple if not already there
for f in "$MOODLIGHT" "$OLED"; do
    if ! grep -q '^KillSignal=' "$f"; then
        sed -i '/^Type=simple$/a KillSignal=SIGTERM\nTimeoutStopSec=5' "$f"
    fi
done

systemctl daemon-reload
systemctl restart minitower_moodlight.service
systemctl restart minitower_oled.service

echo
echo "Patched. To verify cleanup works, run:"
echo "  sudo systemctl stop minitower_oled"
echo "The OLED should blank within ~1 second. Then start it again with:"
echo "  sudo systemctl start minitower_oled"
echo
echo "Originals saved as *.bak.<timestamp> alongside the service files."
