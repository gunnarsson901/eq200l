#!/usr/bin/env python3
"""EQ200L — OLED menu interface."""

import os
import socket
import subprocess
import time

try:
    import lgpio as _lgpio
    _LGPIO_OK = True
except ImportError:
    _LGPIO_OK = False

MARAUDER_SPI  = "/dev/spidev0.0"
MARAUDER_GPIO = 24   # ready/IRQ pin

from PIL import Image, ImageDraw, ImageFont

from display import init_display
from buttons import init_buttons, poll, cleanup

try:
    import qrcode
    import qrcode.constants
    HAS_QR = True
except ImportError:
    HAS_QR = False

GITHUB_URL = "https://github.com/gunnarsson901/eq200l"
W, H       = 128, 64
ROW_H      = 11
SPLASH_SEC = 2.5


# ── fonts ─────────────────────────────────────────────────────────────────────

def _font(size=None):
    if size:
        for path in [
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
            "/usr/share/fonts/truetype/freefont/FreeMono.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
        ]:
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _text_w(draw, text, font):
    bb = draw.textbbox((0, 0), text, font=font)
    return bb[2] - bb[0]


# ── screens ───────────────────────────────────────────────────────────────────

def draw_splash(device):
    img = Image.new('1', (W, H), 0)
    d   = ImageDraw.Draw(img)
    big = _font(22)
    sm  = _font(9)

    title = "EQ200L"
    tx = (W - _text_w(d, title, big)) // 2
    d.text((tx, 4), title, font=big, fill=255)

    for row, line in enumerate(["Passive Network Tap", "ECP5  x  Pi 4"]):
        lx = (W - _text_w(d, line, sm)) // 2
        d.text((lx, 40 + row * 12), line, font=sm, fill=255)

    device.display(img)
    time.sleep(SPLASH_SEC)


def draw_menu(device, items, cursor, scroll, title=""):
    img  = Image.new('1', (W, H), 0)
    d    = ImageDraw.Draw(img)
    font = _font()
    y0   = 0

    if title:
        d.text((2, 1), title, font=font, fill=255)
        d.line([(0, 11), (W - 1, 11)], fill=255)
        y0 = 13

    vis = (H - y0) // ROW_H

    for i in range(vis):
        idx = scroll + i
        if idx >= len(items):
            break
        item  = items[idx]
        y     = y0 + i * ROW_H
        label = item['label']
        if isinstance(item.get('action'), list):
            label += ' >'
        if idx == cursor:
            d.rectangle([0, y, W - 5, y + ROW_H - 2], fill=255)
            d.text((4, y + 1), label[:20], font=font, fill=0)
        else:
            d.text((4, y + 1), label[:20], font=font, fill=255)

    n = len(items)
    if n > vis:
        bh = max(4, (H - y0) * vis // n)
        ms = max(1, n - vis)
        by = y0 + (H - y0 - bh) * scroll // ms
        d.rectangle([W - 3, by, W - 1, by + bh - 1], fill=255)

    device.display(img)


def draw_lines(device, lines, title=""):
    """Generic scrollable text screen. Any button press returns to menu."""
    img  = Image.new('1', (W, H), 0)
    d    = ImageDraw.Draw(img)
    font = _font()
    y    = 0

    if title:
        d.text((2, 0), title, font=font, fill=255)
        d.line([(0, 10), (W - 1, 10)], fill=255)
        y = 12

    for line in lines:
        if y > H - 10:
            break
        d.text((2, y), str(line)[:21], font=font, fill=255)
        y += 10

    device.display(img)


def draw_qr(device):
    img  = Image.new('1', (W, H), 0)
    d    = ImageDraw.Draw(img)
    font = _font()

    if not HAS_QR:
        draw_lines(device, ["pip install", "  qrcode[pil]"], "Missing: qrcode")
        return

    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=2,
        border=1,
    )
    qr.add_data(GITHUB_URL)
    qr.make(fit=True)

    qr_img = qr.make_image().convert('1')
    qr_img = qr_img.resize((H, H), Image.NEAREST)
    img.paste(qr_img, (0, 0))

    for row, text in enumerate(["GitHub:", "", "gunnarsson", "901/eq200l", "", "any key back"]):
        d.text((68, 2 + row * 10), text, font=font, fill=255)

    device.display(img)


# ── system info ───────────────────────────────────────────────────────────────

def _device_info():
    out = []

    try:
        out.append(f"Host:{socket.gethostname()}")
    except Exception:
        out.append("Host: ?")

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.1)
        s.connect(("10.255.255.255", 1))
        out.append(f"IP:  {s.getsockname()[0]}")
        s.close()
    except Exception:
        out.append("IP:  --")

    try:
        model = open("/proc/device-tree/model").read().strip('\x00')
        out.append(model[:21])
    except Exception:
        out.append("HW:  unknown")

    try:
        secs    = float(open("/proc/uptime").read().split()[0])
        m, s    = divmod(int(secs), 60)
        h, m    = divmod(m, 60)
        out.append(f"Up:  {h}h {m:02d}m {s:02d}s")
    except Exception:
        out.append("Up:  ?")

    return out


def _connections():
    out = []

    for iface in ['eth0', 'wlan0', 'usb0']:
        try:
            r = subprocess.run(
                ['ip', '-4', 'addr', 'show', iface],
                capture_output=True, text=True, timeout=2,
            )
            if 'inet ' in r.stdout:
                ip = next(
                    ln.strip().split()[1]
                    for ln in r.stdout.splitlines() if 'inet ' in ln
                )
                out.append(f"{iface}:{ip.split('/')[0]}")
            else:
                out.append(f"{iface}: down")
        except Exception:
            continue

    try:
        r = subprocess.run(['lsusb'], capture_output=True, text=True, timeout=2)
        fpga = "iCeSugar OK" if '0d28:0204' in r.stdout else "not found"
        out.append(f"FPGA:{fpga}")
    except Exception:
        out.append("FPGA: ?")

    for dev in ['/dev/ttyUSB0', '/dev/ttyACM0', '/dev/ttyAMA0', '/dev/ttyS0']:
        if os.path.exists(dev):
            out.append(f"LoRa:{dev}")
            break
    else:
        out.append("LoRa: no dev")

    return out


def _marauder_status():
    out = []

    spi_ok = os.path.exists(MARAUDER_SPI)
    out.append(f"SPI: {'OK' if spi_ok else 'not found'}")

    if _LGPIO_OK:
        try:
            h   = _lgpio.gpiochip_open(0)
            _lgpio.gpio_claim_input(h, MARAUDER_GPIO, _lgpio.SET_PULL_UP)
            val = _lgpio.gpio_read(h, MARAUDER_GPIO)
            _lgpio.gpiochip_close(h)
            out.append(f"GPIO{MARAUDER_GPIO}: {'HI' if val else 'LO'}")
        except Exception:
            out.append(f"GPIO{MARAUDER_GPIO}: err")
    else:
        out.append("lgpio: missing")

    try:
        r = subprocess.run(
            ['ls', '/sys/bus/spi/devices/'],
            capture_output=True, text=True, timeout=2,
        )
        devs = r.stdout.strip().split()
        out.append(f"SPI devs:{len(devs)}")
    except Exception:
        pass

    return out


# ── action helpers ────────────────────────────────────────────────────────────

def _tbi():
    return ('lines', ["Not yet", "implemented."], "TBI")


def _hint(title, *lines):
    return ('lines', list(lines), title)


# ── menu tree ─────────────────────────────────────────────────────────────────

def build_menu():
    return [
        {'label': 'Capture', 'action': [
            {'label': 'UART Monitor',
             'action': lambda: _hint(
                 "UART Monitor",
                 "stty /dev/ttyS0",
                 " 1000000 raw -echo",
                 "cat /dev/ttyS0|xxd",
             )},
            {'label': 'Start Capture',  'action': _tbi},
            {'label': 'Stop Capture',   'action': _tbi},
            {'label': 'Pcap Export',    'action': _tbi},
        ]},
        {'label': 'FPGA', 'action': [
            {'label': 'Flash Bitstream',
             'action': lambda: _hint(
                 "Flash FPGA",
                 "openFPGALoader",
                 " --cable cmsisdap",
                 " bitstream.bit",
             )},
            {'label': 'Detect Device',
             'action': lambda: _hint(
                 "Detect FPGA",
                 "openFPGALoader",
                 " --cable cmsisdap",
                 " --detect",
             )},
        ]},
        {'label': 'LoRa', 'action': [
            {'label': 'Terminal',
             'action': lambda: _hint(
                 "LoRa Terminal",
                 "python3 LoRa/",
                 " lora_terminal.py",
             )},
            {'label': 'Probe',
             'action': lambda: _hint(
                 "LoRa Probe",
                 "python3 LoRa/",
                 " probe.py",
             )},
            {'label': 'Stream Capture', 'action': _tbi},
        ]},
        {'label': 'Marauder', 'action': [
            {'label': 'WiFi', 'action': [
                {'label': 'Probe Sniff',
                 'action': lambda: _hint(
                     "Probe Sniff",
                     "scanap",
                     " then: sniffprobe",
                 )},
                {'label': 'Beacon Scan',
                 'action': lambda: _hint(
                     "Beacon Scan",
                     "scanap",
                 )},
                {'label': 'Deauth Detect',
                 'action': lambda: _hint(
                     "Deauth Detect",
                     "sniffdeauth",
                 )},
                {'label': 'PMKID Sniff',
                 'action': lambda: _hint(
                     "PMKID Sniff",
                     "sniffpmkid",
                 )},
                {'label': 'Wardriving',
                 'action': lambda: _hint(
                     "Wardriving",
                     "wardrive",
                 )},
            ]},
            {'label': 'Bluetooth', 'action': [
                {'label': 'BLE Scan',
                 'action': lambda: _hint(
                     "BLE Scan",
                     "blescansave",
                 )},
                {'label': 'BT Scan',
                 'action': lambda: _hint(
                     "BT Scan",
                     "btscan",
                 )},
            ]},
            {'label': 'Status',
             'action': lambda: ('lines', _marauder_status(), "Marauder")},
            {'label': 'Update FW',
             'action': lambda: _hint(
                 "Update FW",
                 "Use Web-OTA or",
                 "ESP32Marouder/",
                 "MarauderOTA/",
             )},
        ]},
        {'label': 'Settings', 'action': [
            {'label': 'Device Info',
             'action': lambda: ('lines', _device_info(), "Device Info")},
            {'label': 'Connections',
             'action': lambda: ('lines', _connections(), "Connections")},
            {'label': 'Marauder HW',
             'action': lambda: ('lines', _marauder_status(), "Marauder HW")},
            {'label': 'GitHub QR',
             'action': lambda: ('qr', None, None)},
            {'label': 'Contrast',       'action': _tbi},
        ]},
    ]


# ── main loop ─────────────────────────────────────────────────────────────────

def main():
    device = init_display()
    init_buttons()

    draw_splash(device)

    stack   = [{'items': build_menu(), 'cursor': 0, 'scroll': 0, 'title': 'EQ200L'}]
    overlay = None   # ('lines', lines, title) | ('qr', _, _) | None
    dirty   = True

    def vis_count(title):
        return (H - (13 if title else 0)) // ROW_H

    def on_button(name):
        nonlocal dirty, overlay

        if overlay is not None:
            overlay = None
            dirty   = True
            return

        f     = stack[-1]
        items = f['items']
        vis   = vis_count(f['title'])

        if name == 'up':
            if f['cursor'] > 0:
                f['cursor'] -= 1
                if f['cursor'] < f['scroll']:
                    f['scroll'] = f['cursor']
                dirty = True

        elif name == 'down':
            if f['cursor'] < len(items) - 1:
                f['cursor'] += 1
                if f['cursor'] >= f['scroll'] + vis:
                    f['scroll'] = f['cursor'] - vis + 1
                dirty = True

        elif name in ('right', 'select'):
            item   = items[f['cursor']]
            action = item.get('action')
            if isinstance(action, list):
                stack.append({
                    'items':  action,
                    'cursor': 0,
                    'scroll': 0,
                    'title':  item['label'],
                })
            elif callable(action):
                overlay = action()
            dirty = True

        elif name == 'left':
            if len(stack) > 1:
                stack.pop()
                dirty = True

    try:
        while True:
            poll(on_button)
            if dirty:
                if overlay is not None:
                    kind = overlay[0]
                    if kind == 'lines':
                        draw_lines(device, overlay[1], overlay[2])
                    elif kind == 'qr':
                        draw_qr(device)
                else:
                    f = stack[-1]
                    draw_menu(device, f['items'], f['cursor'],
                              f['scroll'], f['title'])
                dirty = False
            time.sleep(0.02)
    except KeyboardInterrupt:
        pass
    finally:
        device.cleanup()
        cleanup()


if __name__ == '__main__':
    main()
