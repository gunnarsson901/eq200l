#!/usr/bin/env bash
# =============================================================================
# upload.sh — Build bitstream locally (if tools available) then SSH-copy to Pi
#             and program the FPGA from there.
#
# Usage:
#   ./upload.sh <pi-host> [pi-user]
#
# Example:
#   ./upload.sh raspberrypi.local pi
#   ./upload.sh 192.168.1.42     pi
#
# The Pi must have iceprog installed (sudo apt install fpga-icestorm).
# The FPGA board must be connected to the Pi via USB or SPI flash programmer.
# =============================================================================

set -e

PI_HOST="${1:-192.168.0.107}"
PI_USER="${2:-phoenix}"
REMOTE="${PI_USER}@${PI_HOST}"
REMOTE_DIR="/home/${PI_USER}/ICE/hw"

BIN="build/top.bin"

echo "==> Checking for local build tools..."
if command -v yosys &>/dev/null && command -v nextpnr-ice40 &>/dev/null; then
    echo "==> Building bitstream locally..."
    make
else
    echo "    yosys/nextpnr not found locally — will build on Pi."
    BIN=""
fi

echo "==> Syncing project to ${REMOTE}:${REMOTE_DIR} ..."
ssh "${REMOTE}" "mkdir -p ${REMOTE_DIR}"
rsync -av --exclude 'build/' \
    "$(dirname "$0")/" \
    "${REMOTE}:${REMOTE_DIR}/"

if [ -z "${BIN}" ]; then
    echo "==> Building on Pi..."
    ssh "${REMOTE}" "cd ${REMOTE_DIR} && make"
fi

echo "==> Programming FPGA via iceprog on Pi..."
ssh "${REMOTE}" "cd ${REMOTE_DIR} && iceprog build/top.bin"

echo "==> Done."
echo ""
echo "To read the UART stream on the Pi (1 Mbaud 8N1):"
echo "  stty -F /dev/ttyAMA0 1000000 raw -echo && cat /dev/ttyAMA0 | xxd"
