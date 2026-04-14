#!/bin/bash
#
. /lib/lsb/init-functions

log_action_msg "Welcome to GeeekPi ABS Minitower kit installation Program"

codename=$(lsb_release -a 2>/dev/null | grep Codename | awk '{print $NF}')
arch=$(uname -m)

log_action_msg "Detecting system information..."
if [[ $arch != 'aarch64' ]]; then
    log_failure_msg "This script requires a 64-bit (aarch64) OS. Detected: $arch"
    exit 1
fi

case "$codename" in
    bookworm)
        log_action_msg "OS: Raspberry Pi OS 64-bit Bookworm -- fully supported."
        LIBTIFF_PKG="libtiff5-dev"
        sleep 3
        ;;
    trixie)
        log_action_msg "OS: Raspberry Pi OS 64-bit Trixie -- fully supported."
        LIBTIFF_PKG="libtiff-dev"
        sleep 3
        ;;
    *)
        log_failure_msg "Unsupported OS codename: $codename. This script supports Bookworm and Trixie only."
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Helper: clone a git repo with a fixed number of retries then bail out
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

    log_failure_msg "Failed to clone $url after $max_attempts attempts. Check your internet connection and try again."
    exit 1
}

# ---------------------------------------------------------------------------
# Install system packages
# ---------------------------------------------------------------------------
log_action_msg "Installing basic dependencies..."
sudo apt-get update && sudo apt-get -y -q install \
    git cmake scons \
    python3-dev python3 python3-pip python3-pil \
    libjpeg-dev zlib1g-dev libfreetype6-dev \
    liblcms2-dev libopenjp2-7 "${LIBTIFF_PKG}" \
    || { log_failure_msg "apt-get failed. Check your internet connection."; exit 1; }

# ---------------------------------------------------------------------------
# Install Python dependencies via pip (no local folder dependency)
# ---------------------------------------------------------------------------
log_action_msg "Installing Python libraries..."
pip3 install psutil luma.oled --break-system-packages \
    || { log_failure_msg "pip3 install failed."; exit 1; }

# ---------------------------------------------------------------------------
# Create minitower system user
# ---------------------------------------------------------------------------
log_action_msg "Creating minitower system user..."
if ! id -u minitower &>/dev/null; then
    sudo useradd \
        --system \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --comment "Minitower service account" \
        minitower
    log_action_msg "User 'minitower' created."
else
    log_action_msg "User 'minitower' already exists, skipping."
fi

sudo usermod -aG gpio,i2c minitower \
    && log_action_msg "Added minitower to gpio and i2c groups." \
    || log_warning_msg "Could not add minitower to hardware groups -- I2C access may fail."

# ---------------------------------------------------------------------------
# Clone luma.examples to /home/pi/minitower/examples (reference only)
# ---------------------------------------------------------------------------
EXAMPLES_DIR="/home/pi/minitower/examples"
if [[ ! -d "$EXAMPLES_DIR" ]]; then
    sudo mkdir -p "$EXAMPLES_DIR"
    sudo chown pi:pi "$(dirname "$EXAMPLES_DIR")"
    git_clone_with_retry "https://github.com/rm-hull/luma.examples.git" "$EXAMPLES_DIR"
    sudo chown -R pi:pi "$EXAMPLES_DIR"
    log_action_msg "luma.examples cloned to $EXAMPLES_DIR (reference only)."
else
    log_action_msg "luma.examples already present at $EXAMPLES_DIR, skipping."
fi

# ---------------------------------------------------------------------------
# Build and install rpi_ws281x moodlight binary
# ---------------------------------------------------------------------------
cd /tmp
if [[ ! -d /tmp/rpi_ws281x ]]; then
    git_clone_with_retry "https://github.com/jgarff/rpi_ws281x" "/tmp/rpi_ws281x"
fi

cd /tmp/rpi_ws281x
sudo scons \
    && mkdir -p build \
    && cd build \
    && cmake -D BUILD_SHARED=OFF -D BUILD_TEST=ON .. \
    && sudo make install \
    && sudo cp ./test /usr/bin/moodlight \
    && log_action_msg "moodlight binary installed to /usr/bin/moodlight." \
    || { log_failure_msg "rpi_ws281x build failed."; exit 1; }

# ---------------------------------------------------------------------------
# Enable I2C
# ---------------------------------------------------------------------------
log_action_msg "Enabling I2C on Raspberry Pi..."
sudo sed -i '/dtparam=i2c_arm/d' /boot/firmware/config.txt
echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt > /dev/null
log_action_msg "I2C enabled."

# ---------------------------------------------------------------------------
# Install OLED Python scripts
# ---------------------------------------------------------------------------
log_action_msg "Installing OLED display scripts..."
sudo mkdir -p /usr/local/minitower

sudo cp "$(dirname "$0")/democ_code/demo_opts.py" /usr/local/minitower/demo_opts.py
sudo cp "$(dirname "$0")/democ_code/sysinfo.py"   /usr/local/minitower/sysinfo.py

sudo chown -R minitower:minitower /usr/local/minitower
sudo chmod 755 /usr/local/minitower
sudo chmod 644 /usr/local/minitower/*.py

log_action_msg "OLED scripts installed."

# ---------------------------------------------------------------------------
# Moodlight systemd service  (runs as root -- required for DMA/LED hardware)
# ---------------------------------------------------------------------------
log_action_msg "Installing moodlight service..."
sudo tee /etc/systemd/system/minitower_moodlight.service > /dev/null <<'EOF'
[Unit]
Description=Minitower Moodlight Service
DefaultDependencies=no
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
User=root
Type=simple
ExecStart=/usr/bin/moodlight
RemainAfterExit=yes
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

sudo chown root:root /etc/systemd/system/minitower_moodlight.service
sudo chmod 644 /etc/systemd/system/minitower_moodlight.service

# ---------------------------------------------------------------------------
# OLED systemd service  (runs as minitower -- only needs i2c group access)
# ---------------------------------------------------------------------------
log_action_msg "Installing OLED service..."
sudo tee /etc/systemd/system/minitower_oled.service > /dev/null <<'EOF'
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
RemainAfterExit=yes
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo chown root:root /etc/systemd/system/minitower_oled.service
sudo chmod 644 /etc/systemd/system/minitower_oled.service

# ---------------------------------------------------------------------------
# Enable and start services
# ---------------------------------------------------------------------------
log_action_msg "Enabling and starting services..."
sudo systemctl daemon-reload

sudo systemctl enable minitower_moodlight.service
sudo systemctl start  minitower_moodlight.service

sudo systemctl enable minitower_oled.service
sudo systemctl start  minitower_oled.service

log_success_msg "Minitower installation finished successfully."

# ---------------------------------------------------------------------------
# Reboot countdown
# ---------------------------------------------------------------------------
for i in $(seq 5 -1 1); do
    log_action_msg "System will reboot in $i seconds..."
    sleep 1
done

sudo sync
sudo reboot
