#!/usr/bin/env bash
# ice.sh — ICE40 FPGA workflow menu
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="${SCRIPT_DIR}/.ice_settings"

# ── Defaults ──────────────────────────────────────────────────────────────────
PI_HOST="192.168.0.107"
PI_USER="phoenix"
SPI_DEV="/dev/spidev4.0"
SPI_SPEED="1000"
UART_DEV="/dev/ttyAMA0"
UART_BAUD="1000000"
PROJECT="hw"
CRESET_PIN="24"
CDONE_PIN="25"

[[ -f "$SETTINGS_FILE" ]] && source "$SETTINGS_FILE"

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    B='\033[1m'; DIM='\033[2m'; R='\033[0m'
    RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'
else
    B=''; DIM=''; R=''; RED=''; GRN=''; YLW=''; CYN=''
fi

info()    { echo -e " ${CYN}=>${R} $*"; }
ok()      { echo -e " ${GRN}✓${R}  $*"; }
err()     { echo -e " ${RED}✗${R}  $*" >&2; }
ask()     { local _p="$1" _v="${2:-REPLY}"; read -rp "$(echo -e " ${YLW}?${R}  ${_p}: ")" "$_v" 2>/dev/null || true; }
pause()   { read -rp "$(echo -e " ${DIM}press enter to continue${R}")" _ 2>/dev/null || true; }
hr()      { echo -e " ${DIM}─────────────────────────────────────${R}"; }

remote()  { ssh "${PI_USER}@${PI_HOST}" "$@"; }
SS_B_PIN="${SS_B_PIN:-8}"

save()    {
    cat > "$SETTINGS_FILE" <<EOF
PI_HOST='${PI_HOST}'
PI_USER='${PI_USER}'
SPI_DEV='${SPI_DEV}'
SPI_SPEED='${SPI_SPEED}'
UART_DEV='${UART_DEV}'
UART_BAUD='${UART_BAUD}'
PROJECT='${PROJECT}'
CRESET_PIN='${CRESET_PIN}'
CDONE_PIN='${CDONE_PIN}'
SS_B_PIN='${SS_B_PIN}'
EOF
}

proj_dir() {
    echo "${SCRIPT_DIR}/${PROJECT}"
}

remote_dir() {
    echo "/home/${PI_USER}/ICE/${PROJECT}"
}

# ── Build ─────────────────────────────────────────────────────────────────────
do_build() {
    local rdir; rdir="$(remote_dir)"
    info "Syncing sources to ${PI_USER}@${PI_HOST}:${rdir} ..."
    remote "mkdir -p ${rdir}"
    rsync -a --exclude 'build/' "$(proj_dir)/" "${PI_USER}@${PI_HOST}:${rdir}/"
    info "Building on Pi..."
    remote "cd ${rdir} && make"
    ok "Build complete → ${rdir}/build/top.bin"
}

# ── Upload ────────────────────────────────────────────────────────────────────
# Configures the ICE40 via SPI-slave mode (volatile SRAM — survives until power-off).
# PGM1 / SPI0 header pinout:
#   GPIO ${CRESET_PIN} = CRESET_B    GPIO ${SS_B_PIN} = SPI_SS_B (SPI0 CE0)
#   GPIO 9  = SPI_SO (input)   GPIO 10 = SPI_SI    GPIO 11 = SCK
# To write permanently to flash, connect the FTDI USB cable and run iceprog.
do_upload() {
    local bin_name="${1:-top.bin}"
    local rdir; rdir="$(remote_dir)"
    local bin="${rdir}/build/${bin_name}"

    if ! remote "test -f ${bin}" 2>/dev/null; then
        local ans="y"
        ask "No bitstream on Pi (${bin_name}) — build first? [Y/n]" ans
        [[ "${ans,,}" == "n" ]] && return
        do_build
    fi

    info "Configuring ICE40 via SPI-slave (PGM1/SPI0) ..."
    info "  CRESET=GPIO${CRESET_PIN}  SS_B=GPIO${SS_B_PIN}  CDONE=GPIO${CDONE_PIN}"
    remote "sudo python3 - <<'PYEOF'
import mmap, time, sys

BIN     = '${bin}'
CRESET  = ${CRESET_PIN}
CDONE   = ${CDONE_PIN}
SS_B    = ${SS_B_PIN}
SPI_SO  = 9
SPI_SI  = 10
SCK     = 11

GPIO_BASE = 0xFE200000
fd = open('/dev/mem','r+b'); m = mmap.mmap(fd.fileno(),0x1000,offset=GPIO_BASE); fd.close()
def rd(o):   m.seek(o); return int.from_bytes(m.read(4),'little')
def wr(o,v): m.seek(o); m.write((v&0xFFFFFFFF).to_bytes(4,'little'))
def hi(p):   wr(0x1C+(p>>5)*4, 1<<(p&31))
def lo(p):   wr(0x28+(p>>5)*4, 1<<(p&31))
def lv(p):   return (rd(0x34+(p>>5)*4)>>(p&31))&1
def out(p):
    r,b=p//10,(p%10)*3; v=rd(r*4); v=(v&~(7<<b))|(1<<b); wr(r*4,v)
def inp(p):
    r,b=p//10,(p%10)*3; v=rd(r*4); v&=~(7<<b); wr(r*4,v)
def pullup(p):
    # BCM2711 GPPUPPDN: 0xE4=GPIO0-15, 0xE8=GPIO16-31; 2 bits per pin, 01=pull-up
    reg=0xE4+(p//16)*4; bit=(p%16)*2
    v=rd(reg); v=(v&~(3<<bit))|(1<<bit); wr(reg,v)

# Ensure SPI_SO (MISO) has pull-UP so its idle level is 1
pullup(SPI_SO)

for p in [SS_B, SPI_SI, SCK, CRESET]: out(p)
for p in [SPI_SO, CDONE]:              inp(p)

hi(SS_B); hi(CRESET); lo(SCK); lo(SPI_SI)
time.sleep(0.01)

with open(BIN, \"rb\") as f:
    bs = f.read()
print(\"Bitstream: %d bytes\" % len(bs))

# ICE40 SPI-slave config sequence
lo(CRESET); time.sleep(0.001)
lo(SS_B);   time.sleep(0.001)
hi(CRESET)

# Wait for SPI_SO to go HIGH (SRAM clear done, ~1200 us)
time.sleep(0.002)
deadline = time.monotonic() + 0.1
while lv(SPI_SO) == 0 and time.monotonic() < deadline:
    time.sleep(0.0001)

# Clock bitstream in (MSB first)
t0 = time.monotonic()
for byte in bs:
    for i in range(7,-1,-1):
        if (byte>>i)&1: hi(SPI_SI)
        else:            lo(SPI_SI)
        hi(SCK); lo(SCK)

# >= 49 dummy clocks
lo(SPI_SI)
for _ in range(7):
    for _ in range(8): hi(SCK); lo(SCK)

elapsed = (time.monotonic() - t0) * 1000

# Deassert SS_B before polling CDONE (FPGA drives CDONE high after SS_B goes high)
hi(SS_B)
time.sleep(0.002)

# Poll CDONE up to 500 ms
deadline2 = time.monotonic() + 0.5
while lv(CDONE) == 0 and time.monotonic() < deadline2:
    time.sleep(0.001)
cdone = lv(CDONE)

for p in [SS_B, SPI_SI, SCK, CRESET]: inp(p)

# Restore SPI0 GPIO alt functions (ALT0=0b100) so /dev/spidev0.0 works immediately
def alt0(p):
    r,b=p//10,(p%10)*3; v=rd(r*4); v=(v&~(7<<b))|(4<<b); wr(r*4,v)
for p in [8,9,10,11]: alt0(p)

if cdone:
    print(\"CDONE=1  FPGA configured OK  (%.0f ms)\" % elapsed)
    print(\"Note: volatile config — repower loads from flash\")
else:
    print(\"ERROR: CDONE=0 after %.0f ms — config failed\" % elapsed)
    sys.exit(1)
PYEOF"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        # Bit-bang upload corrupts the SPI0 BCM2835 hardware CS register.
        # Reload the kernel module to reset the peripheral cleanly.
        remote "sudo modprobe -r spidev spi_bcm2835 2>/dev/null; sudo modprobe spi_bcm2835 spidev" || true
        ok "Upload complete"
    else
        err "Upload failed (rc=${rc})"
    fi
}

do_build_upload() { do_build && do_upload; }

# ── Freq test ─────────────────────────────────────────────────────────────────
# Builds and uploads a divided-clock bitstream, then drives Pi GPIO0 (~1 kHz)
# as the FPGA clock via the J3/SMI connector (G1 = GBIN7/PIO3_25).
#
# No oscillator or LAN8720 needed — only the existing Pi↔FPGA J3 wiring.
#
#   Ball  pi03     Freq (@ 1 kHz Pi GPIO0 clock)
#   D2    pi03_07  500 Hz  /2      (J2.4)
#   G5    pi03_08  250 Hz  /4      (J2.5)
#   D1    pi03_09  125 Hz  /8      (J2.9)
#   G4    pi03_10   62 Hz  /16
#   E3    pi03_11   31 Hz  /32
#   H5    pi03_12   15 Hz  /64
#   H2    pi03_23    7 Hz  /128
#
do_build_freq() {
    local rdir; rdir="$(remote_dir)"
    info "Syncing sources to ${PI_USER}@${PI_HOST}:${rdir} ..."
    remote "mkdir -p ${rdir}"
    rsync -a --exclude 'build/' "$(proj_dir)/" "${PI_USER}@${PI_HOST}:${rdir}/"
    info "Building freq_test on Pi..."
    remote "cd ${rdir} && make freq_test"
    ok "Build complete → ${rdir}/build/freq_test.bin"
}

# Start a ~1 kHz square wave on Pi GPIO11 (→ FPGA R11/SCK via PGM1 connector pin 9).
# Runs in the background on the Pi; stays alive across SSH sessions.
# GPIO11 doubles as SPI0 SCK — upload must complete before starting the clock.
do_start_pi_clock() {
    info "Starting Pi GPIO11 clock (~1 kHz → FPGA R11/SCK) on ${PI_USER}@${PI_HOST} ..."
    remote "sudo pkill -f 'freq_test_clock' 2>/dev/null; true"
    # Write the clock driver to /tmp
    cat << 'PYEOF' | remote "cat > /tmp/freq_test_clock.py"
import mmap, time, signal, sys

# Pi GPIO11 = SPI0 CLK = FPGA R11 (SCK/PIO2_48) via PGM1 connector pin 9
CLK = 11
GB  = 0xFE200000   # Pi 4 GPIO base

fd = open("/dev/mem","r+b")
m  = mmap.mmap(fd.fileno(), 0x1000, offset=GB)
fd.close()

def rd(o):   m.seek(o); return int.from_bytes(m.read(4),"little")
def wr(o,v): m.seek(o); m.write(v.to_bytes(4,"little"))
def hi(p):   wr(0x1C+(p>>5)*4, 1<<(p&31))
def lo(p):   wr(0x28+(p>>5)*4, 1<<(p&31))
def cfg_out(p):
    r,b = p//10,(p%10)*3
    v = rd(r*4); v = (v&~(7<<b))|(1<<b); wr(r*4,v)
def cfg_inp(p):
    r,b = p//10,(p%10)*3
    v = rd(r*4); v &= ~(7<<b); wr(r*4,v)

cfg_out(CLK)
print("GPIO11 clock running at ~1 kHz", flush=True)

def bye(*a):
    cfg_inp(CLK); sys.exit(0)
signal.signal(signal.SIGTERM, bye)
signal.signal(signal.SIGINT,  bye)

T = 5e-4   # 0.5 ms half-period → ~1 kHz
try:
    while True:
        hi(CLK); time.sleep(T)
        lo(CLK); time.sleep(T)
except Exception:
    bye()
PYEOF
    remote "nohup sudo python3 /tmp/freq_test_clock.py > /tmp/freq_test_clock.log 2>&1 & sleep 0.5; cat /tmp/freq_test_clock.log"
    ok "Pi GPIO11 clock driver started"
}

do_stop_pi_clock() {
    info "Stopping Pi GPIO0 clock driver ..."
    remote "sudo pkill -f 'freq_test_clock' 2>/dev/null && echo 'stopped' || echo 'not running'"
}

do_freq_test() {
    [[ "$PROJECT" != "hw" ]] && { err "Freq test only applies to the 'hw' project"; return 1; }
    do_build_freq && do_upload "freq_test.bin" && do_start_pi_clock
    echo
    info "Freq test running:"
    echo -e "  ${DIM}clock source  Pi GPIO11 → FPGA R11/SCK (PGM1 connector pin 9)${R}"
    echo -e "  ${DIM}outputs       D2/G5/D1/G4/E3/H5/H2 on J2 connector (500→7 Hz)${R}"
    echo -e "  ${DIM}LEDs          LED1 ~1 Hz, LED2 ~2 Hz — blink confirms FPGA running${R}"
    echo
    info "To stop the clock driver:"
    echo -e "  ${DIM}ssh ${PI_USER}@${PI_HOST} sudo pkill -f freq_test_clock${R}"
}

# ── Simulate ──────────────────────────────────────────────────────────────────
do_simulate() {
    local dir; dir="$(proj_dir)"
    case "$PROJECT" in
        hw)
            info "Running simulation for hw (uses sim/ testbench)..."
            (cd "${SCRIPT_DIR}/sim" && make sim)
            ok "Simulation done — run 'Open waves' to view results"
            ;;
        sim)
            info "Running simulation..."
            (cd "$dir" && make sim)
            ok "Simulation done"
            ;;
    esac
}

# ── Open waveforms ────────────────────────────────────────────────────────────
do_waves() {
    local vcd
    case "$PROJECT" in
        hw|sim)
            vcd="${SCRIPT_DIR}/sim/sim/waves.vcd"
            if [[ ! -f "$vcd" ]]; then
                err "No waveform at ${vcd} — run Simulate first"
                return 1
            fi
            info "Opening ${vcd} ..."
            gtkwave "$vcd" &
            ;;
    esac
}

# ── Monitor SPI ──────────────────────────────────────────────────────────────
do_monitor() {
    echo
    echo -e " ${B}  SPI Monitor${R}"
    hr
    echo -e "  source  ${PI_USER}@${PI_HOST} via ${SPI_DEV}"
    hr

    local rdir; rdir="$(remote_dir)"

    # Detect project type: eq200l-style projects have spi_cap.py
    local has_cap=0
    [[ -f "$(proj_dir)/spi_cap.py" ]] && has_cap=1

    if [[ $has_cap -eq 1 ]]; then
        echo "  [1] Frame dump    — decoded Ethernet frames to terminal"
        echo "  [2] Wireshark     — live Ethernet frame decode"
        echo "  [b] back"
        hr
        local sub; ask "choice" sub
        [[ "$sub" == "b" || "$sub" == "B" ]] && return

        scp -q "$(proj_dir)/spi_cap.py" "${PI_USER}@${PI_HOST}:${rdir}/spi_cap.py" 2>/dev/null || true

        case "$sub" in
            1)
                info "Frame dump — Ctrl-C to stop"
                ssh -t "${PI_USER}@${PI_HOST}" \
                    "python3 ${rdir}/spi_cap.py --dev ${SPI_DEV} --speed ${SPI_SPEED}000"
                ;;
            2)
                if ! command -v wireshark &>/dev/null; then
                    err "wireshark not found — install with: sudo apt install wireshark"
                    return 1
                fi
                if ! /usr/bin/dumpcap -h &>/dev/null 2>&1; then
                    err "dumpcap permission denied — run these once to fix:"
                    echo
                    echo -e "  sudo dpkg-reconfigure wireshark-common   ${DIM}# choose Yes${R}"
                    echo -e "  sudo usermod -aG wireshark \$USER"
                    echo -e "  newgrp wireshark                          ${DIM}# or re-login${R}"
                    echo
                    return 1
                fi
                local fifo="/tmp/spi_ws_$$.pipe"
                rm -f "$fifo"; mkfifo "$fifo"
                info "Live capture on ${SPI_DEV} — close Wireshark to stop"
                ssh "${PI_USER}@${PI_HOST}" \
                    "python3 ${rdir}/spi_cap.py --pcap --dev ${SPI_DEV} --speed ${SPI_SPEED}000" \
                    > "$fifo" &
                local cap_pid=$!
                wireshark -k -i "$fifo" 2>/dev/null
                kill "$cap_pid" 2>/dev/null
                rm -f "$fifo"
                ok "Capture stopped"
                ;;
            *)
                err "Unknown option"
                ;;
        esac
    else
        echo "  [1] Hex dump      — raw bytes to terminal"
        echo "  [2] Wireshark     — live Ethernet frame decode"
        echo "  [3] spi_message   — button-press listener (BTN events)"
        echo "  [b] back"
        hr
        local sub; ask "choice" sub
        [[ "$sub" == "b" || "$sub" == "B" ]] && return

        scp -q "$(proj_dir)/spi_read.py" "${PI_USER}@${PI_HOST}:${rdir}/spi_read.py" 2>/dev/null || true

        case "$sub" in
            1)
                info "Hex dump — Ctrl-C to stop"
                ssh -t "${PI_USER}@${PI_HOST}" \
                    "python3 ${rdir}/spi_read.py --dev ${SPI_DEV}"
                ;;
            3)
                local script="/home/${PI_USER}/ICE/projects/spi_message/spi_msg.py"
                if ! ssh "${PI_USER}@${PI_HOST}" "test -f ${script}" 2>/dev/null; then
                    err "spi_msg.py not found on Pi — build+upload spi_message project first"
                    return 1
                fi
                info "spi_message listener — Ctrl-C to stop"
                ssh -t "${PI_USER}@${PI_HOST}" \
                    "python3 ${script} --dev ${SPI_DEV}"
                ;;
            2)
                if ! command -v wireshark &>/dev/null; then
                    err "wireshark not found — install with: sudo apt install wireshark"
                    return 1
                fi
                local pcap_script="${SCRIPT_DIR}/spi2pcap.py"
                if [[ ! -f "$pcap_script" ]]; then
                    err "spi2pcap.py not found at ${pcap_script}"
                    return 1
                fi
                if ! /usr/bin/dumpcap -h &>/dev/null 2>&1; then
                    err "dumpcap permission denied — run these once to fix:"
                    echo
                    echo -e "  sudo dpkg-reconfigure wireshark-common   ${DIM}# choose Yes${R}"
                    echo -e "  sudo usermod -aG wireshark \$USER"
                    echo -e "  newgrp wireshark                          ${DIM}# or re-login${R}"
                    echo
                    return 1
                fi
                local fifo="/tmp/spi_ws_$$.pipe"
                rm -f "$fifo"; mkfifo "$fifo"
                info "Live capture on ${SPI_DEV} — send traffic, close Wireshark to stop"
                ssh "${PI_USER}@${PI_HOST}" \
                    "python3 ${rdir}/spi_read.py --raw --dev ${SPI_DEV}" \
                    | python3 "$pcap_script" > "$fifo" &
                local cap_pid=$!
                wireshark -k -i "$fifo" 2>/dev/null
                kill "$cap_pid" 2>/dev/null
                rm -f "$fifo"
                ok "Capture stopped"
                ;;
            *)
                err "Unknown option"
                ;;
        esac
    fi
}

# ── Switch project ────────────────────────────────────────────────────────────
do_switch_project() {
    # Build project list: fixed built-ins first, then anything in projects/
    local projects=()
    local labels=()

    projects+=("hw");      labels+=("hw       — iCE40HX8K-EVB hardware design (RMII + UART)")
    projects+=("sim");     labels+=("sim      — basic top-level simulation")

    local proj_root="${SCRIPT_DIR}/projects"
    if [[ -d "$proj_root" ]]; then
        for d in "${proj_root}"/*/; do
            [[ -d "$d" ]] || continue
            local name; name="$(basename "$d")"
            [[ -f "${d}/Makefile" ]] || continue
            projects+=("projects/${name}")
            labels+=("${name}  — user project")
        done
    fi

    echo
    echo -e " ${B}  Select project${R}"
    hr
    local i=1
    for label in "${labels[@]}"; do
        printf "  [%s] %s\n" "$i" "$label"
        ((i++))
    done
    echo "  [b] back"
    hr
    local sub
    ask "choice" sub
    case "$sub" in
        b|B) return ;;
        ''|*[!0-9]*) err "Unknown option"; return ;;
    esac
    local idx=$((sub - 1))
    if [[ $idx -ge 0 && $idx -lt ${#projects[@]} ]]; then
        PROJECT="${projects[$idx]}"
        save
        ok "Switched to: ${PROJECT}"
    else
        err "Unknown option"
    fi
}

# ── Test / Diagnose ───────────────────────────────────────────────────────────
do_test() {
    while true; do
        echo
        echo -e " ${B}  Test / Diagnose${R}"
        hr
        echo -e "  target   ${CYN}${PI_HOST}${R}"
        hr
        echo "  [1] Ping Pi              — 5× ICMP (IPv4 frames on tap)"
        echo "  [2] ARP ping             — 5× ARP broadcast (always tap-visible)"
        echo "  [3] Flood ping           — 200 packets @ 20 ms (stress traffic)"
        echo "  [4] Check SPI output     — sample 3 s of raw bytes from FPGA"
        echo "  [5] Link status on Pi    — ip link + addr (via SSH)"
        echo "  [6] TCP port check       — nc connect to a port on Pi"
        echo "  [7] Check SMI/SPI devices — list /dev/smi and /dev/spidev* on Pi"
        echo "  [8] Send raw frames on eth0 — inject test traffic via AF_PACKET"
        echo "  [b] back"
        hr
        local sub
        ask "choice" sub
        echo
        case "$sub" in
            1)
                info "Pinging ${PI_HOST} ..."
                ping -c 5 "$PI_HOST"
                ;;
            2)
                if command -v arping &>/dev/null; then
                    info "ARP ping → ${PI_HOST} ..."
                    arping -c 5 "$PI_HOST" 2>/dev/null \
                        || sudo arping -c 5 "$PI_HOST" 2>/dev/null \
                        || err "arping failed — try: sudo arping -c 5 ${PI_HOST}"
                else
                    err "arping not found — install: sudo apt install arping"
                fi
                ;;
            3)
                info "Flood ping → ${PI_HOST} (200 pkts, 20 ms interval) ..."
                ping -c 200 -i 0.02 "$PI_HOST" | tail -3
                ;;
            4)
                local rdir; rdir="$(remote_dir)"
                scp -q "$(proj_dir)/spi_read.py" \
                    "${PI_USER}@${PI_HOST}:${rdir}/spi_read.py" 2>/dev/null || true
                info "Sampling SPI for 3 s on ${SPI_DEV} ..."
                ssh "${PI_USER}@${PI_HOST}" \
                    "timeout 3 python3 ${rdir}/spi_read.py --dev ${SPI_DEV} 2>/dev/null" || true
                ;;
            5)
                info "Ethernet interfaces on ${PI_HOST} ..."
                remote "ip -c link show; echo; ip -4 addr show"
                ;;
            6)
                local port
                ask "TCP port to check [80]" port
                port="${port:-80}"
                info "Checking ${PI_HOST}:${port} ..."
                if nc -zw 2 "$PI_HOST" "$port" 2>/dev/null; then
                    ok "Port ${port} is open"
                else
                    err "Port ${port} is closed / unreachable"
                fi
                ;;
            7)
                info "Checking SMI and SPI devices on ${PI_HOST} ..."
                remote '
                    found=0

                    # SMI
                    if [ -e /dev/smi ]; then
                        echo " \033[0;32m✓\033[0m  /dev/smi present (SMI overlay loaded)"
                        found=1
                    else
                        echo " \033[0;31m✗\033[0m  /dev/smi not found"
                        echo "     → add  dtoverlay=smi  to /boot/firmware/config.txt and reboot"
                    fi

                    echo

                    # SPI devices
                    spis=$(ls /dev/spidev* 2>/dev/null)
                    if [ -n "$spis" ]; then
                        for d in $spis; do
                            echo " \033[0;32m✓\033[0m  $d present"
                            found=1
                        done
                    else
                        echo " \033[0;31m✗\033[0m  no /dev/spidev* devices found"
                        echo "     → add  dtoverlay=spi4-1cs,cs0_pin=7  (or spi0-1cs) and reboot"
                    fi

                    echo

                    # Active overlays (if dtoverlay is available)
                    if command -v dtoverlay >/dev/null 2>&1; then
                        echo " Active overlays:"
                        dtoverlay -l 2>/dev/null | sed "s/^/   /" || true
                    fi
                '
                ;;
            8)
                local iface count interval
                ask "Interface [eth0]" iface; iface="${iface:-eth0}"
                ask "Frame count [100]" count; count="${count:-100}"
                ask "Interval ms [10]" interval; interval="${interval:-10}"
                info "Sending ${count} raw frames on ${iface} @ ${interval} ms interval ..."
                remote "sudo python3 - <<'PYEOF'
import socket, time, sys
iface   = '${iface}'
count   = ${count}
gap     = ${interval} / 1000.0
# Broadcast dst, Pi src (zeroed — kernel fills real src MAC via AF_PACKET)
pkt = (b'\\xff\\xff\\xff\\xff\\xff\\xff'   # dst MAC (broadcast)
     + b'\\x02\\x00\\x00\\x00\\x00\\x01'  # src MAC (locally-administered test addr)
     + b'\\x08\\x00'                       # EtherType: IPv4
     + b'\\xde\\xad\\xbe\\xef' * 15)       # 60 B payload
try:
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    s.bind((iface, 0))
except PermissionError:
    print('ERROR: need root (run with sudo)', file=sys.stderr)
    sys.exit(1)
except OSError as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
for i in range(count):
    s.send(pkt)
    if gap > 0:
        time.sleep(gap)
s.close()
print(f'Sent {count} frames on {iface}')
PYEOF"
                ;;
            b|B) return ;;
            *) err "Unknown option" ;;
        esac
        echo
        pause
    done
}

# ── Settings ──────────────────────────────────────────────────────────────────
do_settings() {
    while true; do
        clear
        echo -e " ${B}  Settings${R}"
        hr
        echo -e "  [1] Pi host    ${DIM}${PI_HOST}${R}"
        echo -e "  [2] Pi user    ${DIM}${PI_USER}${R}"
        echo -e "  [3] SPI device ${DIM}${SPI_DEV}${R}"
        echo -e "  [4] SPI speed  ${DIM}${SPI_SPEED} kHz${R}"
        echo -e "  [5] UART device${DIM} ${UART_DEV:-/dev/ttyAMA0}${R}"
        echo -e "  [6] UART baud  ${DIM}${UART_BAUD:-1000000}${R}"
        echo -e "  [7] CRESET pin ${DIM}GPIO ${CRESET_PIN}${R}"
        echo -e "  [8] CDONE pin  ${DIM}GPIO ${CDONE_PIN}${R}"
        echo -e "  [9] SS_B pin   ${DIM}GPIO ${SS_B_PIN}${R}  ${DIM}(PGM1/SPI-slave CE0)${R}"
        echo "  [b] back"
        hr
        local sub v
        ask "choice" sub
        case "$sub" in
            1) ask "Pi host [${PI_HOST}]" v; [[ -n "$v" ]] && PI_HOST="$v"; save; ok "Saved" ;;
            2) ask "Pi user [${PI_USER}]" v; [[ -n "$v" ]] && PI_USER="$v"; save; ok "Saved" ;;
            3) ask "SPI device [${SPI_DEV}]" v; [[ -n "$v" ]] && SPI_DEV="$v"; save; ok "Saved" ;;
            4) ask "SPI speed kHz [${SPI_SPEED}]" v; [[ -n "$v" ]] && SPI_SPEED="$v"; save; ok "Saved" ;;
            5) ask "UART device [${UART_DEV:-/dev/ttyAMA0}]" v; [[ -n "$v" ]] && UART_DEV="$v"; save; ok "Saved" ;;
            6) ask "UART baud [${UART_BAUD:-1000000}]" v; [[ -n "$v" ]] && UART_BAUD="$v"; save; ok "Saved" ;;
            7) ask "CRESET GPIO pin [${CRESET_PIN}]" v; [[ -n "$v" ]] && CRESET_PIN="$v"; save; ok "Saved" ;;
            8) ask "CDONE GPIO pin [${CDONE_PIN}]" v; [[ -n "$v" ]] && CDONE_PIN="$v"; save; ok "Saved" ;;
            9) ask "SS_B GPIO pin [${SS_B_PIN}]" v; [[ -n "$v" ]] && SS_B_PIN="$v"; save; ok "Saved" ;;
            b|B) return ;;
            *) err "Unknown option" ;;
        esac
    done
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main() {
    while true; do
        clear
        echo
        echo -e " ${B} ICE40 FPGA Tool${R}"
        hr
        echo -e "  project  ${CYN}${PROJECT}${R}"
        echo -e "  pi       ${PI_USER}@${PI_HOST}"
        echo -e "  spi      ${SPI_DEV} @ ${SPI_SPEED} kHz"
        hr
        echo "  [1] Build"
        echo "  [2] Upload"
        echo "  [3] Build + Upload"
        echo "  [4] Simulate"
        echo "  [5] Open waves"
        echo "  [6] Monitor SPI"
        echo "  [7] Test / Diagnose"
        echo "  [8] Switch project"
        echo "  [9] Settings"
        echo "  [f] Freq test      — 7 divided clocks on J2 via Pi GPIO0 clock (logic analyser)"
        echo "  [q] Quit"
        hr
        echo
        local choice
        ask ">" choice
        echo
        case "$choice" in
            1) do_build ;;
            2) do_upload ;;
            3) do_build_upload ;;
            4) do_simulate ;;
            5) do_waves ;;
            6) do_monitor ;;
            7) do_test ;;
            8) do_switch_project ;;
            9) do_settings ;;
            f|F) do_freq_test ;;
            q|Q) echo " bye"; exit 0 ;;
            *) err "Unknown option: ${choice}" ;;
        esac
        echo
        pause
    done
}

main
