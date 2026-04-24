#!/bin/bash
set -e

# Enable SPI (needed for SPI display mode)
sudo raspi-config nonint do_spi 0

pip install -r requirements.txt

echo "Done. Run with: python main.py"
