#!/usr/bin/env python3
"""EQ200L — terminal mirror of the OLED menu interface.

Controls: ↑↓ / k j / w s  move
          → / Enter / l d  select / enter sub-menu
          ← / q / Esc      back / quit
"""

import curses
import os
import socket
import subprocess

try:
    import lgpio as _lgpio
    _LGPIO_OK = True
except ImportError:
    _LGPIO_OK = False

try:
    import qrcode
    import qrcode.constants
    HAS_QR = True
except ImportError:
    HAS_QR = False

GITHUB_URL    = "https://github.com/gunnarsson901/eq200l"
MARAUDER_SPI  = "/dev/spidev0.0"
MARAUDER_GPIO = 24


# ── system info ───────────────────────────────────────────────────────────────

def _device_info():
    out = []
    try:
        out.append(f"Host: {socket.gethostname()}")
    except Exception:
        out.append("Host: ?")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.1)
        s.connect(("10.255.255.255", 1))
        out.append(f"IP:   {s.getsockname()[0]}")
        s.close()
    except Exception:
        out.append("IP:   --")
    try:
        out.append(open("/proc/device-tree/model").read().strip('\x00'))
    except Exception:
        out.append("HW:   unknown")
    try:
        secs = float(open("/proc/uptime").read().split()[0])
        m, s = divmod(int(secs), 60)
        h, m = divmod(m, 60)
        out.append(f"Up:   {h}h {m:02d}m {s:02d}s")
    except Exception:
        out.append("Up:   ?")
    return out


def _connections():
    out = []
    for iface in ['eth0', 'wlan0', 'usb0']:
        try:
            r = subprocess.run(['ip', '-4', 'addr', 'show', iface],
                               capture_output=True, text=True, timeout=2)
            if 'inet ' in r.stdout:
                ip = next(ln.strip().split()[1]
                          for ln in r.stdout.splitlines() if 'inet ' in ln)
                out.append(f"{iface}: {ip.split('/')[0]}")
            else:
                out.append(f"{iface}: down")
        except Exception:
            continue
    try:
        r = subprocess.run(['lsusb'], capture_output=True, text=True, timeout=2)
        fpga = "iCeSugar OK" if '0d28:0204' in r.stdout else "not found"
        out.append(f"FPGA: {fpga}")
    except Exception:
        out.append("FPGA: ?")
    for dev in ['/dev/ttyUSB0', '/dev/ttyACM0', '/dev/ttyAMA0', '/dev/ttyS0']:
        if os.path.exists(dev):
            out.append(f"LoRa: {dev}")
            break
    else:
        out.append("LoRa: no dev")
    return out


def _marauder_status():
    out = []
    spi_ok = os.path.exists(MARAUDER_SPI)
    out.append(f"SPI:  {'OK — ' + MARAUDER_SPI if spi_ok else 'not found'}")
    if _LGPIO_OK:
        try:
            h = _lgpio.gpiochip_open(0)
            _lgpio.gpio_claim_input(h, MARAUDER_GPIO, _lgpio.SET_PULL_UP)
            val = _lgpio.gpio_read(h, MARAUDER_GPIO)
            _lgpio.gpiochip_close(h)
            out.append(f"GPIO{MARAUDER_GPIO}: {'HI (ready)' if val else 'LO (busy)'}")
        except Exception:
            out.append(f"GPIO{MARAUDER_GPIO}: error")
    else:
        out.append("lgpio: not installed")
    try:
        r = subprocess.run(['ls', '/sys/bus/spi/devices/'],
                           capture_output=True, text=True, timeout=2)
        devs = r.stdout.strip().split()
        out.append(f"SPI devs: {', '.join(devs) or 'none'}")
    except Exception:
        pass
    return out


# ── action helpers ─────────────────────────────────────────────────────────────

def _tbi():
    return ('lines', ["Not yet implemented."], "TBI")


def _hint(title, *lines):
    return ('lines', list(lines), title)


# ── menu tree (mirrors main.py exactly) ────────────────────────────────────────

def build_menu():
    return [
        {'label': 'Capture', 'action': [
            {'label': 'UART Monitor',
             'action': lambda: _hint(
                 "UART Monitor",
                 "stty /dev/ttyS0 1000000 raw -echo",
                 "cat /dev/ttyS0 | xxd",
             )},
            {'label': 'Start Capture',  'action': _tbi},
            {'label': 'Stop Capture',   'action': _tbi},
            {'label': 'Pcap Export',    'action': _tbi},
        ]},
        {'label': 'FPGA', 'action': [
            {'label': 'Flash Bitstream',
             'action': lambda: _hint(
                 "Flash FPGA",
                 "openFPGALoader --cable cmsisdap bitstream.bit",
             )},
            {'label': 'Detect Device',
             'action': lambda: _hint(
                 "Detect FPGA",
                 "openFPGALoader --cable cmsisdap --detect",
             )},
        ]},
        {'label': 'LoRa', 'action': [
            {'label': 'Terminal',
             'action': lambda: _hint(
                 "LoRa Terminal",
                 "python3 LoRa/lora_terminal.py",
             )},
            {'label': 'Probe',
             'action': lambda: _hint(
                 "LoRa Probe",
                 "python3 LoRa/probe.py",
             )},
            {'label': 'Stream Capture', 'action': _tbi},
        ]},
        {'label': 'Marauder', 'action': [
            {'label': 'WiFi', 'action': [
                {'label': 'Probe Sniff',
                 'action': lambda: _hint("Probe Sniff",   "scanap", "sniffprobe")},
                {'label': 'Beacon Scan',
                 'action': lambda: _hint("Beacon Scan",   "scanap")},
                {'label': 'Deauth Detect',
                 'action': lambda: _hint("Deauth Detect", "sniffdeauth")},
                {'label': 'PMKID Sniff',
                 'action': lambda: _hint("PMKID Sniff",   "sniffpmkid")},
                {'label': 'Wardriving',
                 'action': lambda: _hint("Wardriving",    "wardrive")},
            ]},
            {'label': 'Bluetooth', 'action': [
                {'label': 'BLE Scan',
                 'action': lambda: _hint("BLE Scan", "blescansave")},
                {'label': 'BT Scan',
                 'action': lambda: _hint("BT Scan",  "btscan")},
            ]},
            {'label': 'Status',
             'action': lambda: ('lines', _marauder_status(), "Marauder")},
            {'label': 'Update FW',
             'action': lambda: _hint(
                 "Update FW",
                 "Use Web-OTA or",
                 "ESP32Marouder/MarauderOTA/",
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


# ── rendering ─────────────────────────────────────────────────────────────────

_BACK_HINT = " ← / q  back "


def _render_menu(win, items, cursor, scroll, title):
    win.erase()
    h, w = win.getmaxyx()
    y0 = 0
    if title:
        try:
            win.addstr(0, 1, title[:w - 2], curses.A_BOLD)
            win.hline(1, 0, curses.ACS_HLINE, w - 1)
        except curses.error:
            pass
        y0 = 2

    vis = h - y0
    for i in range(vis):
        idx = scroll + i
        if idx >= len(items):
            break
        label = items[idx]['label']
        if isinstance(items[idx].get('action'), list):
            label += ' >'
        y = y0 + i
        try:
            if idx == cursor:
                win.attron(curses.A_REVERSE)
                win.addstr(y, 0, f" {label:<{w - 2}} ")
                win.attroff(curses.A_REVERSE)
            else:
                win.addstr(y, 1, label[:w - 2])
        except curses.error:
            pass

    n = len(items)
    if n > vis:
        bh = max(1, (h - y0) * vis // n)
        ms = max(1, n - vis)
        by = y0 + (h - y0 - bh) * scroll // ms
        for r in range(bh):
            try:
                win.addch(by + r, w - 1, curses.ACS_BLOCK)
            except curses.error:
                pass
    win.refresh()


def _render_lines(win, lines, title):
    win.erase()
    h, w = win.getmaxyx()
    y = 0
    if title:
        try:
            win.addstr(0, 1, title[:w - 2], curses.A_BOLD)
            win.hline(1, 0, curses.ACS_HLINE, w - 1)
        except curses.error:
            pass
        y = 2
    for line in lines:
        if y >= h - 1:
            break
        try:
            win.addstr(y, 1, str(line)[:w - 2])
        except curses.error:
            pass
        y += 1
    try:
        win.addstr(h - 1, max(0, w - len(_BACK_HINT) - 1),
                   _BACK_HINT, curses.A_DIM)
    except curses.error:
        pass
    win.refresh()


def _render_qr(win):
    win.erase()
    h, w = win.getmaxyx()
    if HAS_QR:
        qr = qrcode.QRCode(version=None, box_size=1, border=1,
                           error_correction=qrcode.constants.ERROR_CORRECT_L)
        qr.add_data(GITHUB_URL)
        qr.make(fit=True)
        mat = qr.get_matrix()
        for r in range(0, len(mat) - 1, 2):
            if r // 2 >= h - 1:
                break
            row_str = ""
            for c in range(min(len(mat[r]), w)):
                top = mat[r][c]
                bot = mat[r + 1][c] if r + 1 < len(mat) else False
                row_str += ('█' if top and bot else
                            '▀' if top else
                            '▄' if bot else ' ')
            try:
                win.addstr(r // 2, 0, row_str)
            except curses.error:
                pass
    else:
        try:
            win.addstr(1, 1, "pip install qrcode[pil]", curses.A_BOLD)
            win.addstr(3, 1, GITHUB_URL[:w - 2])
        except curses.error:
            pass
    try:
        win.addstr(h - 1, max(0, w - len(_BACK_HINT) - 1),
                   _BACK_HINT, curses.A_DIM)
    except curses.error:
        pass
    win.refresh()


# ── key sets ──────────────────────────────────────────────────────────────────

_UP    = {curses.KEY_UP,    ord('k'), ord('w')}
_DOWN  = {curses.KEY_DOWN,  ord('j'), ord('s')}
_RIGHT = {curses.KEY_RIGHT, curses.KEY_ENTER, 10, 13, ord('l'), ord('d')}
_LEFT  = {curses.KEY_LEFT,  ord('h'), ord('a')}
_QUIT  = {27, ord('q')}

_STATUS = "  ↑↓ navigate    → / Enter select    ← / q back  "


# ── main loop ─────────────────────────────────────────────────────────────────

def _run(stdscr):
    curses.curs_set(0)
    stdscr.keypad(True)

    # splash
    h, w = stdscr.getmaxyx()
    stdscr.clear()
    for i, (line, attr) in enumerate([
        ("EQ200L",             curses.A_BOLD),
        ("",                   curses.A_NORMAL),
        ("Passive Network Tap", curses.A_NORMAL),
        ("ECP5  x  Pi 4",      curses.A_NORMAL),
    ]):
        y = h // 2 - 1 + i
        try:
            stdscr.addstr(y, max(0, (w - len(line)) // 2), line, attr)
        except curses.error:
            pass
    stdscr.refresh()
    curses.napms(2500)

    stack   = [{'items': build_menu(), 'cursor': 0, 'scroll': 0, 'title': 'EQ200L'}]
    overlay = None
    dirty   = True
    cur_hw  = (0, 0)

    outer = win = None

    while True:
        h, w = stdscr.getmaxyx()

        if (h, w) != cur_hw:
            cur_hw = (h, w)
            stdscr.clear()
            stdscr.refresh()
            try:
                outer = curses.newwin(h - 1, w, 0, 0)
                win   = curses.newwin(h - 3, w - 2, 1, 1)
            except curses.error:
                stdscr.addstr(0, 0, "Terminal too small")
                stdscr.refresh()
                stdscr.timeout(200)
                if stdscr.getch() in _QUIT:
                    break
                continue
            dirty = True

        if dirty:
            outer.erase()
            outer.box()
            try:
                outer.addstr(h - 2, max(0, (w - len(_STATUS)) // 2),
                             _STATUS, curses.A_DIM)
            except curses.error:
                pass
            outer.refresh()

            if overlay is not None:
                kind = overlay[0]
                if kind == 'lines':
                    _render_lines(win, overlay[1], overlay[2])
                elif kind == 'qr':
                    _render_qr(win)
            else:
                f = stack[-1]
                _render_menu(win, f['items'], f['cursor'], f['scroll'], f['title'])
            dirty = False

        stdscr.timeout(50)
        key = stdscr.getch()

        if key == -1:
            continue
        if key == curses.KEY_RESIZE:
            dirty = True
            continue

        if overlay is not None:
            overlay = None
            dirty   = True
            continue

        f     = stack[-1]
        items = f['items']
        vis   = (h - 3) - (2 if f['title'] else 0)

        if key in _UP:
            if f['cursor'] > 0:
                f['cursor'] -= 1
                if f['cursor'] < f['scroll']:
                    f['scroll'] = f['cursor']
                dirty = True

        elif key in _DOWN:
            if f['cursor'] < len(items) - 1:
                f['cursor'] += 1
                if f['cursor'] >= f['scroll'] + vis:
                    f['scroll'] = f['cursor'] - vis + 1
                dirty = True

        elif key in _RIGHT:
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

        elif key in _LEFT | _QUIT:
            if len(stack) > 1:
                stack.pop()
                dirty = True
            elif key in _QUIT:
                break


def main():
    curses.wrapper(_run)


if __name__ == '__main__':
    main()
