#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# GeeekPi ABS Minitower - OLED system info display
# Hardware: SSD1306, 128x64, I2C address 0x3C

import os
import time
import subprocess as sp

import psutil
from PIL import ImageFont
from luma.core.interface.serial import i2c
from luma.core.render import canvas
from luma.oled.device import ssd1306

FONT_PATH = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
FONT_SIZE = 11


def bytes2human(n):
    symbols = ('K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
    prefix = {}
    for i, s in enumerate(symbols):
        prefix[s] = 1 << (i + 1) * 10
    for s in reversed(symbols):
        if n >= prefix[s]:
            return '%d%s' % (int(float(n) / prefix[s]), s)
    return '%dB' % n


def cpu_usage():
    av1, av2, av3 = os.getloadavg()
    return 'Ld:%.1f %.1f %.1f' % (av1, av2, av3)


def mem_usage():
    usage = psutil.virtual_memory()
    return 'Mem:%s %.0f%%' % (bytes2human(usage.used), 100 - usage.percent)


def disk_usage():
    usage = psutil.disk_usage('/')
    return 'SD:%s %.0f%%' % (bytes2human(usage.used), usage.percent)


def network(iface):
    stat = psutil.net_io_counters(pernic=True)[iface]
    return '%s Tx:%s Rx:%s' % (iface, bytes2human(stat.bytes_sent), bytes2human(stat.bytes_recv))


def ip_address():
    ip = sp.getoutput('hostname -I').split(' ')[0]
    return 'IP:%s' % ip


def draw_stats(device, font):
    with canvas(device) as draw:
        draw.text((0,  1), cpu_usage(),  font=font, fill='white')
        draw.text((0, 13), mem_usage(),  font=font, fill='white')
        draw.text((0, 25), disk_usage(), font=font, fill='white')
        try:
            draw.text((0, 37), network('wlan0'), font=font, fill='white')
        except KeyError:
            draw.text((0, 37), 'wlan0: unavailable', font=font, fill='white')
        draw.text((0, 49), ip_address(), font=font, fill='white')


def main():
    serial = i2c(port=1, address=0x3C)
    device = ssd1306(serial)
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)

    while True:
        draw_stats(device, font)
        time.sleep(5)


if __name__ == '__main__':
    main()

