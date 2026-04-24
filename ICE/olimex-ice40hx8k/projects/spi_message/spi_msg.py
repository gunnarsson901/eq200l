#!/usr/bin/env python3
"""spi_msg.py — receive button-press messages from the FPGA.

The FPGA returns 0xFF when idle.  Each button press queues "BTN\\n"
(4 bytes, one per poll).  This script prints them as they arrive.

Usage:
    python3 spi_msg.py [--dev /dev/spidev0.0] [--hz 1000000]
"""
import spidev, sys, time, signal, argparse

parser = argparse.ArgumentParser()
parser.add_argument('--dev', default='/dev/spidev0.0')
parser.add_argument('--hz',  type=int, default=1_000_000)
args = parser.parse_args()

bus, dev = (int(x) for x in args.dev.replace('/dev/spidev', '').split('.'))

spi = spidev.SpiDev()
spi.open(bus, dev)
spi.max_speed_hz = args.hz
spi.mode = 0

def cleanup(sig=None, frame=None):
    spi.close()
    print()
    sys.exit(0)

signal.signal(signal.SIGINT, cleanup)

print(f"Listening on {args.dev} at {args.hz//1000} kHz — press the FPGA button...")

last_dot = time.monotonic()
while True:
    rx = spi.xfer2([0xFF])[0]
    if rx != 0xFF:
        sys.stdout.write(chr(rx) if 32 <= rx < 127 or rx == 0x0A else f'\\x{rx:02x}')
        sys.stdout.flush()
        last_dot = time.monotonic()
    else:
        time.sleep(0.005)
        now = time.monotonic()
        if now - last_dot >= 1.0:
            sys.stdout.write('.')
            sys.stdout.flush()
            last_dot = now
