#!/usr/bin/env python3
"""
spi2pcap.py — Convert spi_read.py --raw framed stream to pcap for Wireshark.

Input (stdin): framed byte stream produced by  spi_read.py --raw
  Each frame is prefixed by two bytes:  [len_h] [len_l]
  Frame length N = (len_h << 8) | len_l  (1 ≤ N ≤ 1518)
  Frame data includes the 4-byte Ethernet FCS; pcap strips it.

Output (stdout): pcap stream (linktype ETHERNET = 1)

Usage:
  # Live capture into Wireshark via a named pipe:
  mkfifo /tmp/spi.pipe
  ssh phoenix@192.168.0.107 "python3 ~/ICE/hw/spi_read.py --raw" \\
      | python3 spi2pcap.py > /tmp/spi.pipe &
  wireshark -k -i /tmp/spi.pipe

  # Save to file:
  ssh phoenix@192.168.0.107 "python3 ~/ICE/hw/spi_read.py --raw" \\
      | python3 spi2pcap.py > capture.pcap
  wireshark capture.pcap

  # tshark (command-line):
  ssh phoenix@192.168.0.107 "python3 ~/ICE/hw/spi_read.py --raw" \\
      | python3 spi2pcap.py | tshark -r -
"""

import sys
import struct
import time

LINK_ETHERNET = 1
MIN_FRAME     = 14    # min Ethernet header (dest+src+ethertype), no FCS
MAX_FRAME     = 1518  # max standard Ethernet frame (1514 payload + 4 FCS)


def write_global_header(out):
    out.write(struct.pack('<IHHiIII',
        0xA1B2C3D4,    # magic number (little-endian timestamps)
        2, 4,          # pcap version 2.4
        0,             # UTC offset
        0,             # timestamp accuracy
        65535,         # snaplen
        LINK_ETHERNET, # DLT_EN10MB
    ))
    out.flush()


def write_packet(out, frame: bytes):
    # Strip the 4-byte FCS — pcap convention is to omit it.
    # (Wireshark will add a FCS validity column automatically.)
    if len(frame) > 4:
        payload = frame[:-4]
    else:
        payload = frame
    ts      = time.time()
    ts_sec  = int(ts)
    ts_usec = int((ts - ts_sec) * 1_000_000)
    n = len(payload)
    out.write(struct.pack('<IIII', ts_sec, ts_usec, n, n))
    out.write(payload)
    out.flush()


def read_exact(src, n: int):
    buf = bytearray()
    while len(buf) < n:
        chunk = src.read(n - len(buf))
        if not chunk:
            return None
        buf.extend(chunk)
    return bytes(buf)


def main():
    inp = sys.stdin.buffer
    out = sys.stdout.buffer

    write_global_header(out)

    count      = 0
    last_print = time.monotonic()

    while True:
        header = read_exact(inp, 2)
        if header is None:
            break
        len_h, len_l = header
        n = (len_h << 8) | len_l
        if n < MIN_FRAME or n > MAX_FRAME:
            # Length out of range — framing error, skip one byte and re-sync
            continue
        frame = read_exact(inp, n)
        if frame is None:
            break
        write_packet(out, frame)
        count += 1
        now = time.monotonic()
        if now - last_print >= 1.0:
            print(f'\r  {count} frames captured', file=sys.stderr,
                  end='', flush=True)
            last_print = now


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\n  stopped', file=sys.stderr)
