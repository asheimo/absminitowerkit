#!/bin/bash
#
. /lib/lsb/init-functions

# ---------------------------------------------------------------------------
# Must run as root
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    log_failure_msg "This script must be run as root. Try: sudo bash $0"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve script directory reliably regardless of how the script was invoked
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_action_msg "Welcome to GeeekPi ABS Minitower kit installation program"

# ---------------------------------------------------------------------------
# System checks
# ---------------------------------------------------------------------------
arch=$(uname -m)
if [[ $arch != 'aarch64' ]]; then
    log_failure_msg "This script requires a 64-bit (aarch64) OS. Detected: $arch"
    exit 1
fi

codename=$(lsb_release -cs 2>/dev/null)
log_action_msg "Detected OS: $arch / $codename"

case "$codename" in
    bookworm)
        LIBTIFF_PKG="libtiff5-dev"
        ;;
    trixie)
        LIBTIFF_PKG="libtiff-dev"
        ;;
    *)
        log_failure_msg "Unsupported OS: $codename. This script supports Bookworm and Trixie only."
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Helper: clone a git repo with retries
# Usage: git_clone_with_retry <url> <destination>
# ---------------------------------------------------------------------------
git_clone_with_retry() {
    local url="$1"
    local dest="$2"
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log_action_msg "Cloning $url (attempt $attempt of $max_attempts)..."
        git clone "$url" "$dest" && return 0
        attempt=$(( attempt + 1 ))
        sleep 5
    done

    log_failure_msg "Failed to clone $url after $max_attempts attempts. Check your internet connection."
    exit 1
}

# ---------------------------------------------------------------------------
# Install system packages
# ---------------------------------------------------------------------------
log_action_msg "Installing system packages..."
apt-get update && apt-get -y -q install \
    git cmake scons gcc \
    python3-dev python3 python3-pip python3-pil \
    libjpeg-dev zlib1g-dev libfreetype6-dev \
    liblcms2-dev libopenjp2-7 "${LIBTIFF_PKG}" \
    || { log_failure_msg "apt-get failed. Check your internet connection."; exit 1; }

# ---------------------------------------------------------------------------
# Install Python libraries
# ---------------------------------------------------------------------------
log_action_msg "Installing Python libraries..."
pip3 install psutil luma.oled --break-system-packages \
    || { log_failure_msg "pip3 install failed."; exit 1; }

# ---------------------------------------------------------------------------
# Create minitower system user
# ---------------------------------------------------------------------------
log_action_msg "Creating minitower system user..."
if ! id -u minitower &>/dev/null; then
    useradd \
        --system \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --comment "Minitower service account" \
        minitower \
        && log_action_msg "User 'minitower' created." \
        || { log_failure_msg "Failed to create minitower user."; exit 1; }
else
    log_action_msg "User 'minitower' already exists, skipping."
fi

usermod -aG gpio,i2c minitower \
    && log_action_msg "Added minitower to gpio and i2c groups." \
    || log_warning_msg "Could not add minitower to hardware groups -- I2C access may fail."

# ---------------------------------------------------------------------------
# Build and install moodlight binary
# ---------------------------------------------------------------------------
log_action_msg "Building moodlight driver..."

# Always build from a clean clone to avoid stale build artifacts
rm -rf /tmp/rpi_ws281x
git_clone_with_retry "https://github.com/jgarff/rpi_ws281x" "/tmp/rpi_ws281x"

# Build the rpi_ws281x library
cd /tmp/rpi_ws281x \
    && scons \
    && mkdir -p build \
    && cd build \
    && cmake -D BUILD_SHARED=OFF -D BUILD_TEST=OFF .. \
    && make install \
    || { log_failure_msg "rpi_ws281x library build failed."; exit 1; }

# Compile our moodlight.c against the installed library
log_action_msg "Compiling moodlight..."
gcc -O2 -Wall \
    -I /tmp/rpi_ws281x \
    "${SCRIPT_DIR}/src/moodlight.c" \
    -L /usr/local/lib \
    -l ws2811 -l m \
    -o /usr/bin/moodlight \
    && log_action_msg "moodlight binary installed to /usr/bin/moodlight." \
    || { log_failure_msg "moodlight compile failed."; exit 1; }

# ---------------------------------------------------------------------------
# Enable I2C (takes effect after reboot)
# ---------------------------------------------------------------------------
log_action_msg "Enabling I2C in /boot/firmware/config.txt..."
sed -i '/dtparam=i2c_arm/d' /boot/firmware/config.txt
echo "dtparam=i2c_arm=on" >> /boot/firmware/config.txt
log_action_msg "I2C enabled (will be active after reboot)."

# ---------------------------------------------------------------------------
# Install OLED display script
# ---------------------------------------------------------------------------
log_action_msg "Installing OLED display script..."
mkdir -p /usr/local/minitower
cp "${SCRIPT_DIR}/democ_code/sysinfo.py" /usr/local/minitower/sysinfo.py \
    || { log_failure_msg "Failed to copy sysinfo.py -- is the repo intact?"; exit 1; }

chown -R minitower:minitower /usr/local/minitower
chmod 755 /usr/local/minitower
chmod 644 /usr/local/minitower/*.py
log_action_msg "OLED script installed."

# ---------------------------------------------------------------------------
# Moodlight systemd service (runs as root -- required for DMA/LED hardware)
# ---------------------------------------------------------------------------
log_action_msg "Installing moodlight service..."
tee /etc/systemd/system/minitower_moodlight.service > /dev/null <<'EOF'
[Unit]
Description=Minitower Moodlight Service
DefaultDependencies=no
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
User=root
Type=simple
ExecStart=/usr/bin/moodlight
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

chown root:root /etc/systemd/system/minitower_moodlight.service
chmod 644 /etc/systemd/system/minitower_moodlight.service

# ---------------------------------------------------------------------------
# OLED systemd service (runs as minitower -- only needs i2c group access)
# ---------------------------------------------------------------------------
log_action_msg "Installing OLED service..."
tee /etc/systemd/system/minitower_oled.service > /dev/null <<'EOF'
[Unit]
Description=Minitower OLED Service
DefaultDependencies=no
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
User=minitower
WorkingDirectory=/usr/local/minitower
Type=simple
ExecStart=/usr/bin/python3 /usr/local/minitower/sysinfo.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

chown root:root /etc/systemd/system/minitower_oled.service
chmod 644 /etc/systemd/system/minitower_oled.service

# ---------------------------------------------------------------------------
# Enable services (do not start -- I2C not active until after reboot)
# ---------------------------------------------------------------------------
log_action_msg "Enabling services (will start automatically after reboot)..."
systemctl daemon-reload
systemctl enable minitower_moodlight.service
systemctl enable minitower_oled.service

log_success_msg "Minitower installation finished successfully."

# ---------------------------------------------------------------------------
# Reboot prompt
# ---------------------------------------------------------------------------
read -r -p "Installation complete. Reboot now? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
    sync
    reboot
else
    log_action_msg "Reboot skipped. Please reboot manually to activate I2C and start services."
fi
