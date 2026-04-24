#!/usr/bin/env python3
"""
Transparent terminal for DX-LR20-433M22SP LoRa development board.

The STM32 firmware acts as a UART<->LoRa bridge:
  - Bytes sent here are transmitted over LoRa (433 MHz, SF9, BW125, 22 dBm)
  - Bytes received via LoRa are printed here as raw text

Usage:
  python3 lora_terminal.py          # interactive terminal
  python3 lora_terminal.py --reset  # toggle DTR to trigger startup banner
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
    # Prevent accidental STM32 reset via DTR auto-reset circuit (like Arduino).
    # Keep DTR high (idle) — only pulse it when explicitly requested.
    ser.dtr = True
    ser.rts = False

    if args.reset:
        print('[*] Resetting STM32 via DTR pulse...')
        ser.dtr = False   # assert reset (active low via cap)
        time.sleep(0.1)
        ser.dtr = True    # release
        time.sleep(0.8)   # wait for boot + LoRa init (~500ms)

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
