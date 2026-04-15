# absminitowerkit

ABS Mini Tower Kit driver and installation script for Raspberry Pi 4.

> **Note:** This is a community-improved version of the original GeeekPi install script.
> It has been updated for broader OS compatibility, cleaner service management, and safer
> installation practices. See the [Changes from Original](#changes-from-original) section for details.

---

## Requirements

- Raspberry Pi 4 (Model B)
- Raspberry Pi OS 64-bit — **Bookworm** or **Trixie**
- Internet access during installation (downloads dependencies from apt and GitHub)

---

## Installation

```bash
cd ~
git clone https://github.com/geeekpi/absminitowerkit.git
cd absminitowerkit/
./install_bookworm.sh
```

The script will install all dependencies, build the moodlight binary, configure services,
and **reboot automatically** when complete.

---

## Uninstallation

```bash
cd ~/absminitowerkit
./uninstall.sh
```

The uninstall script will:
- Stop and disable both services
- Remove service files and the moodlight binary
- Remove the `minitower` system user
- Prompt before removing `/home/pi/minitower` (the luma.examples reference folder)

---

## What Gets Installed

| Path | Purpose |
|------|---------|
| `/usr/bin/moodlight` | LED strip binary (built from rpi_ws281x) |
| `/usr/local/minitower/sysinfo.py` | OLED display script |
| `/usr/local/minitower/demo_opts.py` | OLED display helper |
| `/etc/systemd/system/minitower_moodlight.service` | Moodlight systemd service |
| `/etc/systemd/system/minitower_oled.service` | OLED systemd service |
| `/boot/firmware/config.txt` | I2C enabled: `dtparam=i2c_arm=on` |
| `/home/pi/minitower/examples` | luma.examples reference code (reference only) |

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

- **OS compatibility** — supports both Bookworm and Trixie (64-bit); fails fast with a
  clear message on unsupported versions rather than silently continuing
- **DNS clobbering removed** — the original script overwrote `/etc/resolv.conf` with
  hardcoded DNS servers; this has been removed entirely
- **Dedicated service user** — a `minitower` system account (no shell, no home directory)
  is created during install; the OLED service runs as this user rather than root
- **Moodlight still runs as root** — this is unavoidable; the rpi_ws281x library requires
  DMA hardware access which cannot be granted to unprivileged users
- **Redundant sudo removed** — the original moodlight service called `sudo /usr/bin/moodlight`
  inside a `User=root` service; the redundant `sudo` has been removed
- **Git clone retry limit** — the original script would loop forever if GitHub was
  unreachable; clones now retry 3 times then exit with a clear error message
- **luma.examples path** — examples are now cloned to `/home/pi/minitower/examples`
  rather than `/home/pi/Downloads/examples`
- **Clean pip install** — `luma.oled` is installed directly via pip rather than using
  `pip install -e .` against a local clone, which would have created a live path dependency
- **uninstall.sh typo fixed** — `2&>/dev/null` corrected to `2>/dev/null` throughout

---

## Gallery

![image](https://github.com/geeekpi/absminitowerkit/assets/6893075/967a4e86-c2e3-4965-9deb-83c989ebca2c)

![image](https://github.com/geeekpi/absminitowerkit/assets/6893075/d68ac48e-b2ba-4d38-baf3-c76500424401)
