#!/usr/bin/env python3
"""SPI Ethernet capture — reads FPGA frame stream, decodes Ethernet headers.

FPGA frame format:
  0xFE  — start-of-frame marker
  <N bytes of Ethernet frame data>
  (next frame begins with the next 0xFE)
  0xFF  — idle (FIFO empty); skip

Run:  python3 spi_capture.py [--raw]
  --raw  also hexdump every raw frame to stdout
"""
import sys, time, struct, argparse
sys.path.insert(0, '/home/phoenix/eq200l/PI/interface')

import spidev
import lgpio
from PIL import Image, ImageDraw, ImageFont
from display import SSD1309

CS_PIN   = 24
SPI_BUS  = 0
SPI_DEV  = 0
SPI_HZ   = 500_000
BURST    = 256          # bytes per SPI read burst
SOF      = 0xFE
IDLE     = 0xFF
MAX_FRAME = 1600        # bytes; drop frames longer than this

ETHERTYPE_NAMES = {
    0x0800: 'IPv4',
    0x0806: 'ARP',
    0x86DD: 'IPv6',
    0x8100: 'VLAN',
    0x88CC: 'LLDP',
}


def _font(size=10):
    for path in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeMono.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def show(device, lines):
    img  = Image.new('1', (128, 64), 0)
    draw = ImageDraw.Draw(img)
    font = _font(10)
    for i, line in enumerate(lines[:5]):
        draw.text((0, i * 12), line, font=font, fill=1)
    device.display(img)


def mac(b):
    return ':'.join(f'{x:02x}' for x in b)


def decode_eth(frame):
    if len(frame) < 14:
        return None
    dst = mac(frame[0:6])
    src = mac(frame[6:12])
    etype = struct.unpack('>H', frame[12:14])[0]
    name  = ETHERTYPE_NAMES.get(etype, f'0x{etype:04X}')
    return dst, src, name, len(frame)


def parse_stream(buf, leftover):
    """Split buf (prepended with leftover) into complete frames.
    Returns (frames, new_leftover).
    Each frame is a bytearray (Ethernet bytes, excluding the 0xFE marker).
    """
    data = leftover + bytearray(buf)
    frames = []
    i = 0
    current = None

    while i < len(data):
        b = data[i]
        if b == SOF:
            if current is not None and len(current) > 0:
                frames.append(bytes(current))
            current = bytearray()
        elif b == IDLE:
            pass  # skip idle bytes outside a frame
        else:
            if current is not None:
                current.append(b)
                if len(current) > MAX_FRAME:
                    current = None  # drop oversized frame
        i += 1

    # current may hold an in-progress (incomplete) frame — keep as leftover
    new_leftover = current if current is not None else bytearray()
    return frames, new_leftover


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--raw', action='store_true')
    args = parser.parse_args()

    device = SSD1309()
    show(device, ["ETH CAPTURE", "Opening SPI..."])

    spi = spidev.SpiDev()
    spi.open(SPI_BUS, SPI_DEV)
    spi.max_speed_hz = SPI_HZ
    spi.mode = 0
    spi.no_cs = True

    h = lgpio.gpiochip_open(0)
    lgpio.gpio_claim_output(h, CS_PIN, 1)

    show(device, ["ETH CAPTURE", "Listening..."])
    print("Listening for Ethernet frames via SPI…  (Ctrl-C to stop)")

    pkt_count = 0
    leftover  = bytearray()
    last_info = None

    try:
        while True:
            lgpio.gpio_write(h, CS_PIN, 0)
            raw = spi.xfer2([IDLE] * BURST)
            lgpio.gpio_write(h, CS_PIN, 1)

            frames, leftover = parse_stream(raw, leftover)

            for frame in frames:
                pkt_count += 1
                info = decode_eth(frame)
                if info:
                    dst, src, etype, length = info
                    line0 = f"#{pkt_count} {etype} {length}B"
                    line1 = f"D {dst[-8:]}"
                    line2 = f"S {src[-8:]}"
                    print(f"[{pkt_count:4d}] {etype:8s} {length:4d}B  "
                          f"dst={dst}  src={src}")
                else:
                    line0 = f"#{pkt_count} short {len(frame)}B"
                    line1 = line2 = ""
                    print(f"[{pkt_count:4d}] short frame {len(frame)} bytes")

                if args.raw:
                    print("  " + " ".join(f"{b:02X}" for b in frame[:32])
                          + ("…" if len(frame) > 32 else ""))

                last_info = [line0, line1, line2, f"total:{pkt_count}"]
                show(device, ["ETH CAPTURE"] + last_info)

            # tiny sleep to avoid hammering the bus when idle
            if not frames:
                time.sleep(0.005)

    except KeyboardInterrupt:
        print(f"\nCaptured {pkt_count} frames.")
    finally:
        lgpio.gpio_write(h, CS_PIN, 1)
        spi.close()
        lgpio.gpiochip_close(h)
        show(device, ["ETH CAPTURE", "Stopped.", f"{pkt_count} frames"])


if __name__ == '__main__':
    main()
