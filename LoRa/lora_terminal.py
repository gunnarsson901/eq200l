#!/usr/bin/env python3
"""
Transparent terminal for DX-LR20-433M22SP LoRa development board.

The STM32 firmware acts as a UART<->LoRa bridge:
  - Bytes sent here are transmitted over LoRa (433 MHz, SF9, BW125, 22 dBm)
  - Bytes received via LoRa are printed here as raw text

Boot circuit (via CH340 serial download circuit on PCB):
  - DTR Low  → NRST pulse (reset)
  - RTS High → BOOT0 High (bootloader mode)
  - RTS Low  → BOOT0 Low  (run app from flash)

Usage:
  python3 lora_terminal.py          # interactive terminal (no reset)
  python3 lora_terminal.py --reset  # boot app via RTS/DTR sequence
"""

import serial
import threading
import sys
import time
import argparse

PORT     = '/dev/ttyUSB0'
BAUDRATE = 9600


def reader(ser):
    buf = b''
    while True:
        try:
            data = ser.read(256)
            if data:
                buf += data
                # flush line by line, print remainder on timeout
                while b'\n' in buf:
                    line, buf = buf.split(b'\n', 1)
                    line = line.rstrip(b'\r')
                    try:
                        print(f'\r[RX] {line.decode()}\n> ', end='', flush=True)
                    except UnicodeDecodeError:
                        print(f'\r[RX hex] {line.hex()}\n> ', end='', flush=True)
        except serial.SerialException:
            break


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reset', action='store_true', help='Pulse DTR to reset the STM32 on startup')
    parser.add_argument('--port', default=PORT)
    args = parser.parse_args()

    ser = serial.Serial(args.port, BAUDRATE, timeout=0.1, dsrdtr=False, rtscts=False)
    # RTS LOW = BOOT0 LOW = boot app from flash (not bootloader)
    # DTR idles HIGH (NRST released)
    ser.rts = False
    ser.dtr = True

    if args.reset:
        print('[*] Booting app via RTS/DTR reset sequence...')
        ser.rts = False   # BOOT0=LOW → will boot app on reset
        ser.dtr = False   # assert NRST (reset)
        time.sleep(0.1)
        ser.dtr = True    # release NRST → STM32 boots app from flash
        # Do NOT flush buffer here — banner arrives during this wait
        time.sleep(2.0)   # LoRa SPI init can take ~1-2s
    else:
        ser.reset_input_buffer()

    print(f'[*] Connected to {args.port} at {BAUDRATE} baud')
    print('[*] Type a message and press Enter to send via LoRa.')
    print('[*] Received LoRa packets appear as [RX] lines.')
    print('[*] Ctrl+C to quit.\n')

    t = threading.Thread(target=reader, args=(ser,), daemon=True)
    t.start()

    try:
        while True:
            print('> ', end='', flush=True)
            line = input()
            if line:
                payload = (line + '\n').encode()
                ser.write(payload)
                print(f'[TX] {line}')
    except (KeyboardInterrupt, EOFError):
        print('\n[*] Bye.')
    finally:
        ser.close()


if __name__ == '__main__':
    main()
