# absminitowerkit

ABS Mini Tower Kit driver and installation script for Raspberry Pi 4.

> **Note:** This is a community-improved version of the original GeeekPi install script.
> It has been updated for broader OS compatibility, cleaner service management, and safer
> installation practices. See the [Changes from Original](#changes-from-original) section for details.

---

## Requirements

- Raspberry Pi 4 or 5
- Raspberry Pi OS 64-bit — **Bookworm** or **Trixie**
- Internet access during installation (downloads dependencies from apt and GitHub)

---

## Installation

```bash
cd ~
git clone https://github.com/asheimo/absminitowerkit.git
cd absminitowerkit/
sudo bash install_bookworm.sh
```

The script will install all dependencies, build the moodlight binary, configure services,
and prompt you to reboot when complete.

---

## Uninstallation

```bash
cd ~/absminitowerkit
sudo ./uninstall.sh
```

The uninstall script will:
- Stop and disable both services
- Remove service files and the moodlight binary
- Remove the `minitower` system user
- Remove `/usr/local/minitower/`
- Prompt before removing `/home/pi/minitower`

---

## What Gets Installed

| Path | Purpose |
|------|---------|
| `/usr/bin/moodlight` | LED strip binary (built from rpi_ws281x) |
| `/usr/local/minitower/sysinfo.py` | OLED display script |
| `/etc/systemd/system/minitower_moodlight.service` | Moodlight systemd service |
| `/etc/systemd/system/minitower_oled.service` | OLED systemd service |
| `/boot/firmware/config.txt` | I2C enabled: `dtparam=i2c_arm=on` |

---

## Service Management

Check service status:
```bash
sudo systemctl status minitower_moodlight
sudo systemctl status minitower_oled
```

Restart services:
```bash
sudo systemctl restart minitower_moodlight
sudo systemctl restart minitower_oled
```

View logs:
```bash
journalctl -u minitower_moodlight -f
journalctl -u minitower_oled -f
```

---

## Changes from Original

- **Root check** — the script now exits immediately with a clear message if not run as root
- **OS compatibility** — supports both Bookworm and Trixie (64-bit); fails fast with a
  clear message on unsupported versions rather than silently continuing
- **DNS clobbering removed** — the original script overwrote `/etc/resolv.conf` with
  hardcoded DNS servers; this has been removed entirely
- **Dedicated service user** — a `minitower` system account (no shell, no home directory)
  is created during install; the OLED service runs as this user rather than root
- **Moodlight still runs as root** — this is unavoidable; the rpi_ws281x library requires
  DMA hardware access which cannot be granted to unprivileged users
- **Redundant sudo removed** — the script requires root so internal sudo calls have been
  removed throughout; the original moodlight service also called `sudo` inside a `User=root`
  service which has been corrected
- **Git clone retry limit** — the original script would loop forever if GitHub was
  unreachable; clones now retry 3 times then exit with a clear error message
- **Always clean build** — rpi_ws281x is always cloned fresh to avoid stale build artifacts
  from a previous failed run producing a bad binary
- **luma.examples removed** — no longer cloned or installed; not needed since sysinfo.py
  now initializes the SSD1306 display directly
- **demo_opts.py removed** — sysinfo.py previously relied on luma's command-line argument
  helper to detect the display; it now initializes the SSD1306 (128x64, I2C 0x3C) directly,
  removing an unnecessary dependency
- **Clean pip install** — `luma.oled` is installed directly via pip rather than using
  `pip install -e .` against a local clone, which would have created a live path dependency
- **Services only enabled at install time, not started** — I2C is not active until after
  reboot; the original script started services immediately which would fail
- **RemainAfterExit removed** from both service files — incorrect for persistent loop processes
- **Reboot is now a prompt** — the original forced an automatic reboot; the installer now
  asks before rebooting

---

## Gallery

![image](https://github.com/geeekpi/absminitowerkit/assets/6893075/967a4e86-c2e3-4965-9deb-83c989ebca2c)

![image](https://github.com/geeekpi/absminitowerkit/assets/6893075/d68ac48e-b2ba-4d38-baf3-c76500424401)
