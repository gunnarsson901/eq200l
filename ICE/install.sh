#!/usr/bin/env bash
# install.sh — Install all dependencies for the ICE40 network tap project
#
# Supported:
#   Raspberry Pi OS (Bullseye / Bookworm)   — tested
#   Kali Linux on Raspberry Pi 4            — tested
#   Debian 11+ on ARM                       — should work
#
# Run with:  bash install.sh
set -euo pipefail

BOLD='\033[1m'; RESET='\033[0m'; GRN='\033[0;32m'; CYN='\033[0;36m'; YLW='\033[0;33m'
info() { echo -e " ${CYN}=>${RESET} $*"; }
ok()   { echo -e " ${GRN}✓${RESET}  $*"; }
warn() { echo -e " ${YLW}!${RESET}  $*"; }

# ── Detect distro ──────────────────────────────────────────────────────────────
DISTRO_ID="$(. /etc/os-release && echo "$ID")"
DISTRO_NAME="$(. /etc/os-release && echo "$PRETTY_NAME")"
info "Detected: ${DISTRO_NAME}"

# ── Package lists ──────────────────────────────────────────────────────────────
# Core packages available on all supported distros
PKGS_COMMON=(
    yosys
    nextpnr-ice40
    flashrom
    iverilog
    gtkwave
    python3-pip
)

# icepack lives in different packages depending on the distro
if apt-cache show fpga-icestorm &>/dev/null 2>&1; then
    ICESTORM_PKG="fpga-icestorm"
elif apt-cache show icestorm &>/dev/null 2>&1; then
    ICESTORM_PKG="icestorm"
else
    ICESTORM_PKG=""
fi

info "Updating package lists..."
sudo apt-get update -qq

# ── FPGA toolchain ─────────────────────────────────────────────────────────────
info "Installing FPGA toolchain..."
sudo apt-get install -y "${PKGS_COMMON[@]}"

if [[ -n "$ICESTORM_PKG" ]]; then
    sudo apt-get install -y "$ICESTORM_PKG"
    ok "Installed icestorm as: ${ICESTORM_PKG}"
else
    warn "fpga-icestorm / icestorm not found in apt — installing icepack from source"
    sudo apt-get install -y build-essential libftdi-dev git
    tmpdir=$(mktemp -d)
    git clone --depth 1 https://github.com/YosysHQ/icestorm.git "$tmpdir"
    (cd "$tmpdir" && make -j$(nproc) && sudo make install)
    rm -rf "$tmpdir"
fi

# ── python3-spidev ─────────────────────────────────────────────────────────────
info "Installing python3-spidev..."
if apt-cache show python3-spidev &>/dev/null 2>&1; then
    sudo apt-get install -y python3-spidev
    ok "python3-spidev installed via apt"
else
    # Not in Kali repos — install via pip (system-wide)
    warn "python3-spidev not in apt (normal on Kali) — installing via pip"
    sudo pip3 install spidev --break-system-packages 2>/dev/null \
        || sudo pip3 install spidev
    ok "spidev installed via pip"
fi

# ── SPI interface ──────────────────────────────────────────────────────────────
info "Enabling SPI interface..."

# Determine config.txt location (varies across Pi OS versions)
CONFIG=""
for f in /boot/firmware/config.txt /boot/config.txt; do
    [[ -f "$f" ]] && CONFIG="$f" && break
done

if [[ -z "$CONFIG" ]]; then
    warn "Could not find config.txt — enable SPI manually with raspi-config or by editing your boot config"
elif grep -q "^dtparam=spi=on" "$CONFIG"; then
    ok "SPI already enabled in ${CONFIG}"
else
    echo "dtparam=spi=on" | sudo tee -a "$CONFIG" > /dev/null
    ok "SPI enabled in ${CONFIG} — reboot required"
fi

# Add current user to spi + gpio groups (needed on some distros)
for grp in spi gpio; do
    if getent group "$grp" &>/dev/null; then
        sudo usermod -aG "$grp" "$USER" 2>/dev/null && ok "Added ${USER} to group: ${grp}"
    fi
done

# ── Verify ─────────────────────────────────────────────────────────────────────
echo
info "Checking installed tools..."
ALL_OK=true
for tool in yosys nextpnr-ice40 icepack flashrom iverilog python3; do
    if command -v "$tool" &>/dev/null; then
        ver=$(${tool} --version 2>&1 | head -1 || true)
        ok "$tool"
    else
        echo -e " ✗  ${BOLD}${tool}${RESET}  NOT FOUND"
        ALL_OK=false
    fi
done

python3 -c "import spidev; print(' \033[0;32m✓\033[0m  python3-spidev')" 2>/dev/null \
    || { echo -e " ✗  ${BOLD}python3-spidev${RESET}  NOT FOUND"; ALL_OK=false; }

echo
if $ALL_OK; then
    ok "All dependencies installed"
else
    warn "Some tools missing — check output above"
fi

if grep -q "dtparam=spi=on" "${CONFIG:-/dev/null}" 2>/dev/null; then
    echo
    warn "Reboot to activate SPI:"
    echo -e "  ${BOLD}sudo reboot${RESET}"
fi
