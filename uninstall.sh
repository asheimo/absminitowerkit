#!/bin/bash
# uninstall minitowerkit script
. /lib/lsb/init-functions

# ---------------------------------------------------------------------------
# Must run as root
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    log_failure_msg "This script must be run as root. Try: sudo bash $0"
    exit 1
fi

log_action_msg "Uninstalling Minitower driver..."

# ---------------------------------------------------------------------------
# Stop and disable services
# ---------------------------------------------------------------------------
log_action_msg "Stopping and disabling services..."
systemctl stop    minitower_moodlight.service 2>/dev/null
systemctl disable minitower_moodlight.service 2>/dev/null
systemctl stop    minitower_oled.service      2>/dev/null
systemctl disable minitower_oled.service      2>/dev/null

# ---------------------------------------------------------------------------
# Remove service files
# ---------------------------------------------------------------------------
log_action_msg "Removing service files..."
rm -f /etc/systemd/system/minitower_moodlight.service
rm -f /etc/systemd/system/minitower_oled.service
systemctl daemon-reload

# ---------------------------------------------------------------------------
# Remove I2C config line added by installer
# ---------------------------------------------------------------------------
log_action_msg "Removing I2C config from /boot/firmware/config.txt..."
sed -i '/dtparam=i2c_arm=on/d' /boot/firmware/config.txt

# ---------------------------------------------------------------------------
# Remove moodlight binary
# ---------------------------------------------------------------------------
log_action_msg "Removing /usr/bin/moodlight..."
rm -f /usr/bin/moodlight

# ---------------------------------------------------------------------------
# Remove OLED scripts
# ---------------------------------------------------------------------------
log_action_msg "Removing /usr/local/minitower/..."
rm -rf /usr/local/minitower

# ---------------------------------------------------------------------------
# Remove minitower system user
# ---------------------------------------------------------------------------
log_action_msg "Removing minitower system user..."
if id -u minitower &>/dev/null; then
    userdel minitower \
        && log_action_msg "User 'minitower' removed." \
        || log_warning_msg "Could not remove user 'minitower' -- remove manually if needed."
else
    log_action_msg "User 'minitower' not found, skipping."
fi

# ---------------------------------------------------------------------------
# Optionally remove /home/pi/minitower if it exists
# ---------------------------------------------------------------------------
if [[ -d /home/pi/minitower ]]; then
    read -r -p "Found /home/pi/minitower -- remove it? [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
        rm -rf /home/pi/minitower
        log_action_msg "/home/pi/minitower removed."
    else
        log_action_msg "Leaving /home/pi/minitower in place."
    fi
fi

log_success_msg "Minitower driver uninstalled successfully."

# ---------------------------------------------------------------------------
# Reboot prompt (I2C config.txt change requires reboot to take effect)
# ---------------------------------------------------------------------------
read -r -p "Reboot now to apply config.txt changes? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
    sync
    reboot
else
    log_action_msg "Reboot skipped. Please reboot manually to apply changes."
fi
