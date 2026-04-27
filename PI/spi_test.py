#!/usr/bin/env python3
"""SPI connectivity test — sends 4 bytes via SPI0, shows FPGA response on OLED.

Wiring (Pi → FPGA):
  GPIO10 (MOSI) → E1   GPIO9  (MISO) → F1
  GPIO11 (SCLK) → D1   GPIO24 (CS)   → C2

Expected response from FPGA test pattern: 45 51 32 30  ("EQ20")
"""
import sys, time
sys.path.insert(0, '/home/phoenix/eq200l/PI/interface')

import spidev
import lgpio
from PIL import Image, ImageDraw, ImageFont
from display import SSD1309

CS_PIN    = 24
SPI_BUS   = 0
SPI_DEV   = 0
SPI_HZ    = 500_000

SEND      = [0xDE, 0xAD, 0xBE, 0xEF]   # arbitrary; FPGA ignores MOSI
EXPECTED  = [0x45, 0x51, 0x32, 0x30]   # "EQ20"

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

def main():
    device = SSD1309()
    show(device, ["SPI TEST", "Connecting..."])
    time.sleep(0.3)

    # Open hardware SPI0
    spi = spidev.SpiDev()
    spi.open(SPI_BUS, SPI_DEV)
    spi.max_speed_hz = SPI_HZ
    spi.mode = 0
    spi.no_cs = True          # we drive CS manually on GPIO24

    h = lgpio.gpiochip_open(0)
    lgpio.gpio_claim_output(h, CS_PIN, 1)   # CS idle high

    # Transfer (xfer2 modifies SEND in-place, so snapshot it first)
    sent_bytes = list(SEND)
    lgpio.gpio_write(h, CS_PIN, 0)
    time.sleep(0.000010)          # 10 µs CS setup
    resp = spi.xfer2(SEND)
    time.sleep(0.000010)
    lgpio.gpio_write(h, CS_PIN, 1)

    spi.close()
    lgpio.gpiochip_close(h)

    hex_resp = ' '.join(f'{b:02X}' for b in resp)
    ok = resp == EXPECTED

    print(f"Sent:     {' '.join(f'{b:02X}' for b in sent_bytes)}")
    print(f"Got:      {hex_resp}")
    print(f"Expected: {' '.join(f'{b:02X}' for b in EXPECTED)}")
    print(f"Result:   {'OK' if ok else 'MISMATCH'}")

    show(device, [
        "SPI RESULT:",
        hex_resp,
        "OK :)" if ok else "MISMATCH",
        "Expected:",
        ' '.join(f'{b:02X}' for b in EXPECTED),
    ])

if __name__ == '__main__':
    main()
