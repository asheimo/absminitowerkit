#!/bin/bash
# uninstall minitowerkit script
. /lib/lsb/init-functions

log_action_msg "Uninstalling Minitower driver..."
sleep 3

# ---------------------------------------------------------------------------
# Stop and disable services
# ---------------------------------------------------------------------------
log_action_msg "Stopping and disabling services..."
sudo systemctl stop    minitower_moodlight.service 2>/dev/null
sudo systemctl disable minitower_moodlight.service 2>/dev/null
sudo systemctl stop    minitower_oled.service      2>/dev/null
sudo systemctl disable minitower_oled.service      2>/dev/null

# ---------------------------------------------------------------------------
# Remove service files
# ---------------------------------------------------------------------------
log_action_msg "Removing service files..."
[[ -e /etc/systemd/system/minitower_moodlight.service ]] \
    && sudo rm -f /etc/systemd/system/minitower_moodlight.service

[[ -e /etc/systemd/system/minitower_oled.service ]] \
    && sudo rm -f /etc/systemd/system/minitower_oled.service

sudo systemctl daemon-reload

# ---------------------------------------------------------------------------
# Remove I2C config line added by installer
# ---------------------------------------------------------------------------
log_action_msg "Removing I2C config from /boot/firmware/config.txt..."
sudo sed -i '/dtparam=i2c_arm=on/d' /boot/firmware/config.txt

# ---------------------------------------------------------------------------
# Remove moodlight binary
# ---------------------------------------------------------------------------
log_action_msg "Removing /usr/bin/moodlight..."
[[ -e /usr/bin/moodlight ]] && sudo rm -f /usr/bin/moodlight 2>/dev/null

# ---------------------------------------------------------------------------
# Remove OLED scripts
# ---------------------------------------------------------------------------
log_action_msg "Removing /usr/local/minitower/..."
[[ -d /usr/local/minitower ]] && sudo rm -rf /usr/local/minitower 2>/dev/null

# ---------------------------------------------------------------------------
# Remove minitower system user
# ---------------------------------------------------------------------------
log_action_msg "Removing minitower system user..."
if id -u minitower &>/dev/null; then
    sudo userdel minitower \
        && log_action_msg "User 'minitower' removed." \
        || log_warning_msg "Could not remove user 'minitower' -- remove manually if needed."
else
    log_action_msg "User 'minitower' not found, skipping."
fi

# ---------------------------------------------------------------------------
# Optionally remove examples
# ---------------------------------------------------------------------------
if [[ -d /home/pi/minitower ]]; then
    log_action_msg "Found /home/pi/minitower -- remove it? [y/N]"
    read -r -t 15 answer
    if [[ "${answer,,}" == "y" ]]; then
        sudo rm -rf /home/pi/minitower
        log_action_msg "/home/pi/minitower removed."
    else
        log_action_msg "Leaving /home/pi/minitower in place."
    fi
fi

log_success_msg "Minitower driver uninstalled successfully."
