#!/usr/bin/env python3
"""
capture.py — read frame_uart output from the EQ200L FPGA tap.

Wire format (from frame_uart.v):
  SOF:  0xAA 0x55  (Pi→Router)  |  0xAA 0x57  (Router→Pi)
  DATA: raw bytes; 0xAA in data escaped as 0xAA 0x00
  EOF:  0xAA 0x56

Usage:
  python3 capture.py [--port /dev/serial0] [--baud 1000000] [--pcap out.pcap]
"""

import argparse
import struct
import sys
import time
import termios
import tty
import os

BAUD     = 1_000_000
PORT     = "/dev/serial0"

SOF_PI   = (0xAA, 0x55)   # Pi → Router
SOF_RT   = (0xAA, 0x57)   # Router → Pi
EOF_MARK = (0xAA, 0x56)

DIR_LABEL = {0: "Pi→Router", 1: "Router→Pi"}

# ── PCAP helpers ──────────────────────────────────────────────────────────────

PCAP_MAGIC   = 0xA1B2C3D4
PCAP_VERSION = (2, 4)
LINKTYPE_ETH = 1

def pcap_global_header():
    return struct.pack("<IHHiIII",
        PCAP_MAGIC, PCAP_VERSION[0], PCAP_VERSION[1],
        0, 0, 65535, LINKTYPE_ETH)

def pcap_record(data):
    ts = time.time()
    ts_sec  = int(ts)
    ts_usec = int((ts - ts_sec) * 1_000_000)
    return struct.pack("<IIII", ts_sec, ts_usec, len(data), len(data)) + data

# ── Serial open ───────────────────────────────────────────────────────────────

def open_serial(port, baud):
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    os.set_blocking(fd, True)
    attrs = termios.tcgetattr(fd)
    # raw mode
    tty.setraw(fd)
    attrs = termios.tcgetattr(fd)
    # set baud
    BAUD_MAP = {
        9600:    termios.B9600,
        115200:  termios.B115200,
        1000000: termios.B1000000,
    }
    b = BAUD_MAP.get(baud)
    if b is None:
        raise ValueError(f"Unsupported baud rate {baud}")
    attrs[4] = b  # ispeed
    attrs[5] = b  # ospeed
    attrs[2] |= termios.CLOCAL | termios.CREAD
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return fd

# ── Parser state machine ───────────────────────────────────────────────────────

STATE_HUNT   = 0   # waiting for 0xAA
STATE_SOF2   = 1   # got 0xAA, waiting for 0x55/0x57
STATE_DATA   = 2   # inside frame, collecting bytes
STATE_ESCAPE = 3   # got 0xAA inside data, waiting for 0x00/0x56
STATE_EOF2   = 4   # got 0xAA 0x56 — frame complete

def parse_stream(fd, on_frame):
    state  = STATE_HUNT
    buf    = bytearray()
    dirn   = 0

    while True:
        b = os.read(fd, 1)[0]

        if state == STATE_HUNT:
            if b == 0xAA:
                state = STATE_SOF2

        elif state == STATE_SOF2:
            if b == 0x55:
                dirn  = 0
                buf   = bytearray()
                state = STATE_DATA
            elif b == 0x57:
                dirn  = 1
                buf   = bytearray()
                state = STATE_DATA
            elif b == 0xAA:
                pass   # stay in SOF2 (consecutive 0xAA)
            else:
                state = STATE_HUNT   # garbage — resync

        elif state == STATE_DATA:
            if b == 0xAA:
                state = STATE_ESCAPE
            else:
                buf.append(b)

        elif state == STATE_ESCAPE:
            if b == 0x00:
                buf.append(0xAA)   # un-escape
                state = STATE_DATA
            elif b == 0x56:
                on_frame(bytes(buf), dirn)
                state = STATE_HUNT
            elif b == 0x55 or b == 0x57:
                # missed EOF — treat as new SOF
                dirn  = 0 if b == 0x55 else 1
                buf   = bytearray()
                state = STATE_DATA
            else:
                state = STATE_HUNT  # framing error, resync

# ── Frame display ─────────────────────────────────────────────────────────────

pkt_count = 0

def print_frame(data, dirn, pcap_fd=None):
    global pkt_count
    pkt_count += 1
    ts = time.strftime("%H:%M:%S")

    label = DIR_LABEL.get(dirn, f"dir={dirn}")
    print(f"\n[{pkt_count:>5}] {ts}  {label}  {len(data)} bytes")

    # Ethernet header decode (if long enough)
    if len(data) >= 14:
        dst = ":".join(f"{b:02x}" for b in data[0:6])
        src = ":".join(f"{b:02x}" for b in data[6:12])
        etype = (data[12] << 8) | data[13]
        print(f"  ETH  dst={dst}  src={src}  type=0x{etype:04x}", end="")
        if etype == 0x0800:   print("  (IPv4)")
        elif etype == 0x0806: print("  (ARP)")
        elif etype == 0x86DD: print("  (IPv6)")
        else:                 print()
    else:
        print(f"  (short frame — {len(data)} bytes)")

    # Hex dump — first 64 bytes
    show = data[:64]
    for i in range(0, len(show), 16):
        row = show[i:i+16]
        hex_part  = " ".join(f"{b:02x}" for b in row)
        asc_part  = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
        print(f"  {i:04x}  {hex_part:<47}  {asc_part}")
    if len(data) > 64:
        print(f"  ... ({len(data) - 64} more bytes)")

    if pcap_fd is not None:
        pcap_fd.write(pcap_record(data))
        pcap_fd.flush()

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port",  default=PORT)
    ap.add_argument("--baud",  default=BAUD, type=int)
    ap.add_argument("--pcap",  default=None, help="write packets to pcap file")
    args = ap.parse_args()

    pcap_fd = None
    if args.pcap:
        pcap_fd = open(args.pcap, "wb")
        pcap_fd.write(pcap_global_header())
        print(f"Writing pcap to {args.pcap}")

    print(f"Opening {args.port} at {args.baud} baud …")
    fd = open_serial(args.port, args.baud)
    print("Listening — Ctrl-C to stop\n")

    try:
        parse_stream(fd, lambda data, dirn: print_frame(data, dirn, pcap_fd))
    except KeyboardInterrupt:
        print(f"\n\nCaptured {pkt_count} frames.")
    finally:
        os.close(fd)
        if pcap_fd:
            pcap_fd.close()

if __name__ == "__main__":
    main()
