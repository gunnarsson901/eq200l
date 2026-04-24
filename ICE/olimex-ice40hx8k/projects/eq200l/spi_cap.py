#!/usr/bin/env python3
"""
spi_cap.py — eq200l capture reader
Reads the SPI stream from the FPGA and decodes captured Ethernet frames.

Frame format in cap_fifo: [dir, len_h, len_l, data...]
  dir=0x01: A→B (from router)
  dir=0x02: B→A (from target)
  0xFF: FIFO empty (skip)
"""

import argparse
import sys
import time
import struct
import textwrap
from datetime import datetime

try:
    import spidev
except ImportError:
    sys.exit("spidev not installed — pip install spidev")


def parse_args():
    p = argparse.ArgumentParser(description="eq200l SPI capture reader")
    p.add_argument("--dev",   default="/dev/spidev0.0", help="SPI device")
    p.add_argument("--speed", default=1_000_000, type=int, help="SPI speed Hz")
    p.add_argument("--raw",   action="store_true", help="Raw hex dump (no frame decode)")
    p.add_argument("--pcap",  action="store_true", help="Write pcap to stdout (for Wireshark pipe)")
    p.add_argument("--chunk", default=256, type=int, help="Bytes per SPI read (default 256)")
    return p.parse_args()


PCAP_GLOBAL_HDR = struct.pack("<IHHiIII",
    0xa1b2c3d4,   # magic
    2, 4,         # version
    0,            # thiszone
    0,            # sigfigs
    65535,        # snaplen
    1,            # network: LINKTYPE_ETHERNET
)


def pcap_record(data: bytes) -> bytes:
    ts = time.time()
    ts_sec  = int(ts)
    ts_usec = int((ts - ts_sec) * 1_000_000)
    return struct.pack("<IIII", ts_sec, ts_usec, len(data), len(data)) + data


class FrameDecoder:
    """State-machine decoder for the cap_fifo byte stream."""
    S_DIR, S_LENH, S_LENL, S_DATA = range(4)

    DIR_NAMES = {0x01: "A→B", 0x02: "B→A"}

    def __init__(self, pcap_out=False, raw=False):
        self.state   = self.S_DIR
        self.dir_    = 0
        self.length  = 0
        self.remain  = 0
        self.buf     = bytearray()
        self.count   = 0
        self.pcap_out = pcap_out
        self.raw     = raw
        if pcap_out:
            sys.stdout.buffer.write(PCAP_GLOBAL_HDR)
            sys.stdout.buffer.flush()

    def feed(self, byte: int):
        if byte == 0xFF:
            # FIFO empty padding — only valid if we're between frames
            if self.state == self.S_DIR:
                return
            # Inside a frame 0xFF is valid data, fall through

        if self.state == self.S_DIR:
            if byte in (0x01, 0x02):
                self.dir_   = byte
                self.state  = self.S_LENH
            # else: stray byte, ignore (re-sync)

        elif self.state == self.S_LENH:
            self.length = byte << 8
            self.state  = self.S_LENL

        elif self.state == self.S_LENL:
            self.length |= byte
            if self.length == 0 or self.length > 1514:
                # Bogus length — re-sync
                self.state = self.S_DIR
                return
            self.remain = self.length
            self.buf    = bytearray()
            self.state  = self.S_DATA

        elif self.state == self.S_DATA:
            self.buf.append(byte)
            self.remain -= 1
            if self.remain == 0:
                self._emit()
                self.state = self.S_DIR

    def _emit(self):
        self.count += 1
        data = bytes(self.buf)
        ts   = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        name = self.DIR_NAMES.get(self.dir_, f"?{self.dir_:#x}")

        if self.pcap_out:
            sys.stdout.buffer.write(pcap_record(data))
            sys.stdout.buffer.flush()
        elif self.raw:
            print(f"[{self.count:>4}] {ts}  {name}  {self.length:>4}B  "
                  + data.hex(" "), flush=True)
        else:
            # Pretty decode
            src_mac = data[6:12].hex(":")  if len(data) >= 12 else "?"
            dst_mac = data[0:6].hex(":")   if len(data) >= 6  else "?"
            etype   = int.from_bytes(data[12:14], "big") if len(data) >= 14 else 0
            etype_s = {0x0800: "IPv4", 0x0806: "ARP", 0x86DD: "IPv6",
                       0x8100: "VLAN"}.get(etype, f"{etype:#06x}")
            print(f"[{self.count:>4}] {ts}  {name}  {self.length:>4}B  "
                  f"{src_mac} → {dst_mac}  {etype_s}", flush=True)


def open_spi(dev, speed):
    bus, cs = (int(x) for x in dev.replace("/dev/spidev", "").split("."))
    s = spidev.SpiDev()
    s.open(bus, cs)
    s.max_speed_hz = speed
    s.mode = 0
    return s


def main():
    args  = parse_args()
    spi   = open_spi(args.dev, args.speed)
    dec   = FrameDecoder(pcap_out=args.pcap, raw=args.raw)

    if not args.pcap:
        print(f"eq200l capture on {args.dev} @ {args.speed//1000} kHz — Ctrl-C to stop",
              flush=True)
        print(f"{'idx':>6}  {'time':12}  {'dir':4}  {'len':>5}  frame summary",
              flush=True)
        print("─" * 72, flush=True)

    try:
        while True:
            chunk = spi.readbytes(args.chunk)
            for b in chunk:
                dec.feed(b)
            if not any(b != 0xFF for b in chunk):
                time.sleep(0.005)   # back off when FIFO is dry
    except KeyboardInterrupt:
        if not args.pcap:
            print(f"\n{dec.count} frames captured", flush=True)
    finally:
        spi.close()


if __name__ == "__main__":
    main()
