#!/usr/bin/env python3
"""
spi_read.py — Read Ethernet frames from FPGA over SPI.

Wire protocol (set by frame_store.v + spi_slave.v):
  The FIFO contains back-to-back frames, each preceded by a 2-byte length:
    [len_h] [len_l] [frame_byte_0] … [frame_byte_N-1]
  where N = (len_h << 8) | len_l  (1 ≤ N ≤ 1518)

  Between frames (FIFO empty) the FPGA returns 0xFF.
  len_h is always 0x00–0x05 (max frame 1518 = 0x05EE), so 0xFF is
  unambiguous as the FIFO-empty sentinel when looking for len_h.

Usage:
  python3 spi_read.py                  # pretty hex dump, one frame at a time
  python3 spi_read.py --raw            # raw framed stream (pipe to spi2pcap.py)
  python3 spi_read.py --dev /dev/spidev0.0   # override SPI device
"""
import spidev, sys, time, argparse, struct

MAX_HZ       = 4_000_000   # 4 MHz — well within Pi SPI capability
DEFAULT_DEV  = "/dev/spidev0.0"   # SPI0 CE0 = GPIO8, MISO = GPIO9, CLK = GPIO11
MAX_FRAMELEN = 1518
POLL_CHUNK   = 64          # bytes per poll burst while hunting for a frame


def open_spi(dev: str, speed: int) -> spidev.SpiDev:
    # /dev/spidevB.C → bus B, device C
    parts = dev.replace("/dev/spidev", "").split(".")
    bus, device = int(parts[0]), int(parts[1])
    spi = spidev.SpiDev()
    spi.open(bus, device)
    spi.max_speed_hz = speed
    spi.mode = 0   # CPOL=0, CPHA=0
    return spi


def read_byte(spi: spidev.SpiDev) -> int:
    return spi.readbytes(1)[0]


def read_exact(spi: spidev.SpiDev, n: int) -> bytes:
    """Read exactly n bytes from SPI (may issue multiple transactions)."""
    buf = bytearray()
    while len(buf) < n:
        want = min(256, n - len(buf))
        buf.extend(spi.readbytes(want))
    return bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw",   action="store_true",
                    help="write raw framed bytes to stdout (pipe to spi2pcap.py)")
    ap.add_argument("--speed", type=int, default=MAX_HZ, help="SPI clock Hz")
    ap.add_argument("--dev",   default=DEFAULT_DEV,      help="SPI device path")
    args = ap.parse_args()

    spi = open_spi(args.dev, args.speed)

    frame_no   = 0
    total_b    = 0
    last_stat  = time.monotonic()

    try:
        while True:
            # ── Hunt for len_h ────────────────────────────────────────────────
            # Keep polling until we see a byte in 0x00..0x05 (valid len_h).
            # 0xFF = FIFO empty (skip).  Any other value is a sync error —
            # treat it as FIFO empty and keep hunting.
            len_h = 0xFF
            while len_h == 0xFF or len_h > 5:
                chunk = spi.readbytes(POLL_CHUNK)
                for b in chunk:
                    if b != 0xFF and b <= 5:
                        len_h = b
                        break

            # ── Read len_l (do NOT skip 0xFF — it can be a valid length) ─────
            len_l = read_byte(spi)

            frame_len = (len_h << 8) | len_l
            if frame_len == 0 or frame_len > MAX_FRAMELEN:
                # Spurious framing — skip and re-hunt
                continue

            # ── Read frame data ────────────────────────────────────────────────
            frame = read_exact(spi, frame_len)

            frame_no += 1
            total_b  += frame_len

            if args.raw:
                # Framed format: len_h len_l data[frame_len]
                # spi2pcap.py parses this same format.
                sys.stdout.buffer.write(bytes([len_h, len_l]) + frame)
                sys.stdout.buffer.flush()
            else:
                _hex_dump(frame, frame_no)

            # Periodic stats (hex-dump mode)
            now = time.monotonic()
            if not args.raw and now - last_stat >= 5.0:
                print(f"--- {frame_no} frames  {total_b} bytes ---",
                      file=sys.stderr)
                last_stat = now

    except KeyboardInterrupt:
        print(f"\n--- done: {frame_no} frames  {total_b} bytes ---",
              file=sys.stderr)
    finally:
        spi.close()


def _hex_dump(frame: bytes, no: int):
    etype = struct.unpack_from(">H", frame, 12)[0] if len(frame) >= 14 else 0
    src = ":".join(f"{b:02x}" for b in frame[6:12]) if len(frame) >= 12 else "?"
    dst = ":".join(f"{b:02x}" for b in frame[0:6])  if len(frame) >= 6  else "?"
    print(f"\n── frame {no}  {len(frame)} bytes  "
          f"{dst} ← {src}  ethertype 0x{etype:04x}")
    for i in range(0, len(frame), 16):
        chunk = frame[i:i+16]
        hex_p = " ".join(f"{b:02x}" for b in chunk)
        asc_p = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print(f"  {i:04x}  {hex_p:<47}  |{asc_p}|")


if __name__ == "__main__":
    main()
