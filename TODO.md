# Minitower TODO

## Moodlight

- [x] **Temperature-reactive effect** — colour gradient blue→cyan→green→yellow→orange→red mapped to CPU temp (40–85°C)
- [ ] **Rainbow effect** — cycle through full colour spectrum across all LEDs
- [ ] **Pulse effect** — fade a single colour in and out
- [ ] **Solid colour effect** — static user-defined colour
- [ ] **Config file support** — `/etc/minitower/moodlight.conf` for effect, colour, speed, brightness

> **Note:** Fan LEDs on the Pi 5 are not software controllable. The rpi_ws281x library
> does not support the Pi 5 RP1 chipset. The fans run their own onboard controller.
> The moodlight service has been disabled. Revisit if Pi 5 support matures in rpi_ws281x.

## OLED

- [ ] **CPU temperature** — show temperature alongside or instead of load average
- [ ] **Active network interface** — show wlan0 or eth0, whichever is active, or both
- [ ] **Uptime** — show how long the Pi has been running
- [ ] **Boot message** — display "Booting..." on startup until service is ready
- [ ] **Shutdown message** — display "Shutting down..." on SIGTERM before clearing screen
- [ ] **Hostname splash** — show hostname for a few seconds on boot before switching to stats
- [ ] **Multiple pages** — cycle through info pages on a timer (e.g. stats / network / temperature history)
- [ ] **Bar graphs** — simple visual bars for CPU or memory usage instead of plain text
- [ ] **Large font mode** — larger font for the most important stat, smaller for the rest
- [ ] **Display invert option** — white background, black text as a configurable option

## Installer

- [ ] **Disable moodlight service on Pi 5** — detect Pi model at install time and skip
  enabling minitower_moodlight.service if running on Pi 5

## General

- [ ] Nothing pending
