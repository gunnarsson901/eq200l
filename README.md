```
  ███████╗ ██████╗    ██████╗  ██████╗  ██████╗ ██╗     
  ██╔════╝██╔═══██╗  ╚════██╗██╔═══██╗██╔═══██╗██║     
  █████╗  ██║   ██║   █████╔╝██║   ██║██║   ██║██║     
  ██╔══╝  ██║▄▄ ██║  ██╔═══╝ ██║   ██║██║   ██║██║     
  ███████╗╚██████╔╝  ███████╗╚██████╔╝╚██████╔╝███████╗
  ╚══════╝ ╚══▀▀═╝   ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝
                 Passive Ethernet Network Tap
```

---

## Introduction

**EQ200L** is a hardware + firmware project for building a passive, transparent Ethernet network tap. Traffic flowing between two network endpoints passes through the device unmodified. The FPGA sits in-line, captures a copy of every frame in both directions, and feeds it to a Raspberry Pi for processing and analysis.

The system uses LAN8720 PHY breakouts for Ethernet connectivity, exposes a menu-driven OLED interface on the Pi, and includes a LoRa radio link for wireless data relay.

**Hardware progression:**

| Stage | FPGA | Host Pi | Notes |
|-------|------|---------|-------|
| Testing | Olimex iCE40HX8K-EVB | Pi Zero 2W | Pi Zero 2W RAM too limited for on-device builds |
| **Current** | **iCeSugar Pro (ECP5)** | **Raspberry Pi 4** | Build and flash from Pi 4 over USB |
| Target | iCeSugar Pro (ECP5) | CM4 8GB, 0GB eMMC | Final embedded form factor |

---

## File Tree

```
eq200l/
├── README.md                         ← you are here
│
├── ICE/                              ← FPGA designs & toolchain
│   ├── install.sh                    ← toolchain installer
│   ├── requirements.txt              ← Python deps for build scripts
│   ├── lib/                          ← reusable Verilog modules
│   │   ├── async_fifo.v
│   │   ├── bram_fifo.v
│   │   ├── cdc_sync.v
│   │   ├── rmii_rx.v                 ← RMII dibit → byte stream
│   │   ├── rmii_tx.v                 ← byte stream → RMII dibit
│   │   ├── spi_slave.v               ← SPI interface to Pi
│   │   ├── sync_fifo.v
│   │   └── uart_tx.v
│   │
│   ├── olimex-ice40hx8k/             ← iCE40HX8K-EVB board target
│   │   ├── hw/                       ← basic design: RMII rx → UART tx
│   │   │   ├── src/top.v
│   │   │   ├── top.pcf
│   │   │   └── Makefile
│   │   ├── sim/                      ← testbench for hw/
│   │   │   ├── src/  tb/  sim/
│   │   │   └── Makefile
│   │   └── projects/
│   │       ├── blink_button/
│   │       ├── spi_message/          ← SPI comms demo
│   │       └── eq200l/               ← dual-port tap (main project)
│   │           ├── src/
│   │           ├── top.pcf
│   │           └── Makefile
│   │
│   └── icesugar-pro/                 ← ECP5 iCeSugar Pro board target
│       ├── hw/                       ← 25 MHz single-clock tap
│       │   ├── src/top.v
│       │   ├── top.lpf
│       │   └── Makefile
│       ├── sim_tap/                  ← full tap sim with SMI interface
│       │   ├── src/  tb/
│       │   └── Makefile
│       └── docs/
│           ├── README.md             ← SODIMM-200P pinout table
│           └── wiring.md             ← LAN8720 ↔ FPGA connections
│
├── PI/                               ← Raspberry Pi software
│   └── interface/                    ← OLED menu UI
│       ├── main.py                   ← scrollable menu application
│       ├── display.py                ← SSD1309 I2C driver
│       ├── buttons.py                ← GPIO button polling + debounce
│       ├── requirements.txt          ← luma.oled, RPi.GPIO, Pillow
│       └── TEST/                     ← unit tests
│
├── LoRa/                             ← LoRa wireless subsystem
│   ├── lora_terminal.py              ← UART ↔ LoRa bridge terminal
│   ├── probe.py                      ← DX-LR20 chip probe utility
│   └── docs/                         ← datasheets & module info
│
└── docs/                             ← hardware documentation
    ├── eq200l schematics/            ← project schematics
    ├── icesugar-pro/                 ← ECP5 board docs & pinout image
    ├── ice40hx8k/                    ← iCE40 board docs
    ├── LAN8720 ETH Board/            ← PHY datasheet
    ├── LoRa/                         ← LoRa module docs
    └── examen arbete YRGO/           ← exam work archive
```

---

## System Flow

```mermaid
flowchart LR
    A([Port A\nRJ45]) <-->|Ethernet| PHY_A[LAN8720\nPHY A]
    B([Port B\nRJ45]) <-->|Ethernet| PHY_B[LAN8720\nPHY B]

    PHY_A <-->|RMII| FPGA
    PHY_B <-->|RMII| FPGA

    subgraph FPGA [FPGA  iCE40 / ECP5]
        direction TB
        FWD[Transparent\nForwarding]
        BUF[(Frame\nCapture FIFO)]
        FWD -->|tap copy| BUF
    end

    FPGA <-->|SPI / SMI| PI[Raspberry Pi 4\n→ CM4 target]

    PI --> OLED[SSD1309\nOLED 128×64]
    PI <-->|GPIO| BTN[5-Button\nNavpad]
    PI <-->|UART| LORA[DX-LR20\nLoRa 433 MHz]

    LORA -.->|wireless| REMOTE([Remote Node])
```

---

## Features

### FPGA Core

| Feature | Status |
|---------|--------|
| Transparent dual-port Ethernet forwarding | Implemented |
| RMII frame capture — iCE40HX8K target | Implemented |
| RMII frame capture — ECP5 iCeSugar Pro target | Implemented |
| Frame capture FIFO (BRAM-backed) | Implemented |
| Packet filtering in FPGA | TBI |

### Host Interface

| Feature | Status |
|---------|--------|
| UART frame output to host | Implemented |
| SPI slave interface to Pi | Implemented |
| SMI high-bandwidth interface to Pi | TBI |
| SMI DMA burst transfers | TBI |

### Toolchain & Build

| Feature | Status |
|---------|--------|
| FPGA flash via Pi SPI + flashrom (iCE40) | Implemented |
| FPGA flash via openFPGALoader (ECP5) | Implemented |
| iverilog simulation + GTKWave waveforms | Implemented |
| ice.sh CLI workflow menu | Implemented |

### User Interface

| Feature | Status |
|---------|--------|
| SSD1309 OLED menu UI (128×64, I2C) | Implemented |
| 5-button navigation with debounce | Implemented |
| Web interface for captured traffic | TBI |

### Wireless

| Feature | Status |
|---------|--------|
| LoRa UART bridge terminal | Implemented |
| LoRa chip probe / configuration utility | Implemented |
| Wireless streaming of captures via LoRa | TBI |

### Software / Analysis

| Feature | Status |
|---------|--------|
| Pi-side frame decoder / pcap export | TBI |

### Hardware Platform

| Milestone | Status |
|-----------|--------|
| iCE40HX8K-EVB + Pi Zero 2W (initial testing) | Implemented |
| iCeSugar Pro (ECP5) + Raspberry Pi 4 (current) | Implemented |
| CM4 8GB RAM, 0GB eMMC — final form factor | TBI |

---

## Devices

### FPGA — iCeSugar Pro (ECP5) — *current board*

Lattice ECP5 FPGA on a compact module with a DDR-SODIMM-200P edge connector and a
built-in iCELink DAPLink USB adapter (`0x0d28:0x0204`). Programmed via
`openFPGALoader --cable cmsisdap` directly from the Pi 4 over USB — no SPI
programmer needed.

> `icesprog` does **not** work with the iCELink firmware — it expects VID `0x1d50`.
> Use `openFPGALoader` instead.

**Toolchain:** `yosys` → `nextpnr-ecp5` → `ecppack` → `openFPGALoader`

**udev rule (run once on the host Pi):**
```bash
sudo tee /etc/udev/rules.d/99-icesugar.rules <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666", GROUP="plugdev"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
```

See [`ICE/icesugar-pro/docs/wiring.md`](ICE/icesugar-pro/docs/wiring.md) for LAN8720 ↔ ECP5 pin connections.

---

### FPGA — Olimex iCE40HX8K-EVB — *legacy / testing*

Used during initial development. Houses a Lattice iCE40HX8K in a CT256 BGA package.
Programmed via Pi SPI using `flashrom`; the same SPI lines double as the runtime
data path (`spi_slave.v`). Superseded by the iCeSugar Pro for active development.

**Toolchain:** `yosys` → `nextpnr-ice40` → `icepack` → `flashrom`

| Onboard signal | Net | FPGA pin |
|----------------|-----|----------|
| 100 MHz clock | `CLK` | J3 |
| LED 1 | `LED1` | M12 |
| LED 2 | `LED2` | R16 |
| Button 1 | `BUT1` | K11 |
| Button 2 | `BUT2` | P13 |

**RMII connections (LAN8720 ↔ iCE40)**

| Signal | LAN8720 pin | Verilog net | FPGA pin |
|--------|-------------|-------------|----------|
| 50 MHz ref clock | nINT/RETCLK | `pio3_00` | E4 (GBIN) |
| RX data 0 | RXD0 | `pio3_01` | B2 |
| RX data 1 | RXD1 | `pio3_08` | G5 |
| Carrier sense | CRS_DV | `pio3_07` | D2 |
| TX enable | TX_EN | `pio3_02` | F5 |
| TX data 0 | TXD0 | `pio3_09` | D1 |
| TX data 1 | TXD1 | `pio3_03` | B1 |
| Management data | MDIO | `pio3_04` | C1 |
| Management clock | MDC | `pio3_06` | F4 |

**SMI interface (iCE40 ↔ Pi GPIO)**

| Signal | Pi GPIO (BCM) | Verilog net | FPGA pin |
|--------|---------------|-------------|----------|
| SMI Data 0 | 8 | `pio3_15` | F3 |
| SMI Data 1 | 9 | `pio3_16` | H3 |
| SMI Data 2 | 10 | `pio3_17` | F2 |
| SMI Data 3 | 11 | `pio3_18` | H6 |
| SMI Data 4 | 12 | `pio3_19` | F1 |
| SMI Data 5 | 13 | `pio3_20` | H4 |
| SMI Data 6 | 14 | `pio3_21` | G2 |
| SMI Data 7 | 15 | `pio3_22` | J4 |
| SMI Address 0 | 0 | `pio3_23` | G1 |
| SMI Address 1 | 1 | `pio3_24` | J3 |
| SMI Read (SOE) | 18 | `pio3_25` | G3 |
| SMI Write (SWE) | 19 | `pio3_26` | K3 |

---

### Ethernet PHY — LAN8720

Low-power 10/100 Ethernet transceiver in a small breakout module. Provides the
RMII interface (2-bit data, 50 MHz reference clock) between the RJ45 jack and
the FPGA. Two modules are used — one for each network port.

Key signals: `RXD[1:0]`, `CRS_DV`, `TXD[1:0]`, `TX_EN`, `REF_CLK`, `MDIO`, `MDC`.

---

### Host — Raspberry Pi 4 *(current)* → CM4 8GB, 0GB eMMC *(target)*

Runs the user-space software: reads captured frames from the FPGA over SPI (or
SMI), drives the OLED display, handles button input, and bridges data to LoRa.
Also acts as the FPGA programmer — `openFPGALoader` programs the iCeSugar Pro
directly over USB from the Pi 4.

The Pi Zero 2W was used during initial testing but its limited RAM made
on-device synthesis impractical. The Pi 4 is the current development host.
The final target is a **Compute Module 4 (8GB RAM, 0GB eMMC / Lite)** for a
compact embedded form factor.

**Pi 40-pin header — signals used by this project**

| Pin | BCM | Function |
|-----|-----|----------|
| 8 | 14 | UART TXD / SMI Data 6 → FPGA G2 |
| 10 | 15 | UART RXD / SMI Data 7 → FPGA J4 |
| 12 | 18 | SMI Read SOE → FPGA G3 |
| 19 | 10 | SPI0 MOSI / SMI Data 2 → FPGA P11 |
| 21 | 9 | SPI0 MISO / SMI Data 1 → FPGA P12 |
| 23 | 11 | SPI0 CLK / SMI Data 3 → FPGA R11 |
| 24 | 8 | SPI0 CE0 / SMI Data 0 → FPGA R12 |
| 27 | 0 | ID_SDA / SMI SA0 → FPGA G1 |
| 28 | 1 | ID_SCL / SMI SA1 → FPGA J3 |
| 32 | 12 | SMI Data 4 → FPGA F1 |
| 33 | 13 | SMI Data 5 → FPGA H4 |
| 35 | 19 | SPI1 MISO / SMI Write SWE → FPGA K3 |

> SPI0 pins serve double duty: `flashrom` uses them to program the FPGA flash at
> boot time; `spi_slave.v` reuses the same lines at runtime to stream frame bytes.

---

### Display — SSD1309 OLED (128 × 64)

Monochrome OLED display connected to the Pi over I2C. Driven by `luma.oled` +
Pillow. The UI (`PI/interface/main.py`) renders a scrollable 5-item menu with a
dynamic scrollbar and handles up/down/left/right/select navigation.

---

### Wireless — DX-LR20-433M22SP (LoRa)

433 MHz LoRa module connected to the Pi via UART. `LoRa/lora_terminal.py`
provides a threaded UART ↔ LoRa bridge terminal. `LoRa/probe.py` can query and
configure the module's registers.

---

## Workflow

Use the interactive CLI menu to build, flash, and monitor:

```bash
cd ICE
./ice.sh
```

| Option | Action |
|--------|--------|
| `1` Build | rsync sources → Pi, run `make` (yosys → nextpnr → icepack) |
| `2` Upload | pad bitstream to 2 MB → `flashrom` via SPI |
| `3` Build + Upload | both in sequence |
| `4` Simulate | run iverilog locally; sim_tap has sub-menu |
| `5` Open waves | launch GTKWave with saved VCD |
| `6` Monitor UART | stream FPGA UART output as hex dump from Pi |
| `7` Switch project | `hw` / `sim` / `sim_tap` |
| `8` Settings | Pi host, SPI device, UART device, baud rate |

**Manual UART monitor on Pi:**
```bash
stty -F /dev/ttyS0 1000000 raw -echo cs8 -cstopb -parenb
cat /dev/ttyS0 | xxd
```

**Flash ECP5 manually:**
```bash
openFPGALoader --cable cmsisdap --detect
openFPGALoader --cable cmsisdap bitstream.bit
```

---

## Useful Links

| Resource | URL |
|----------|-----|
| Olimex iCE40HX8K-EVB wiki | https://wiki.olimex.com/wiki/ICE40HX8K-EVB |
| iCESugar Pro GitHub | https://github.com/wuxx/icesugar-pro |
| Colorlight FPGA Projects (Ext-Board origin) | https://github.com/wuxx/Colorlight-FPGA-Projects |
| Yosys synthesis suite | https://github.com/YosysHQ/yosys |
| nextpnr place-and-route | https://github.com/YosysHQ/nextpnr |
| Project Trellis (ECP5 bitstream) | https://github.com/YosysHQ/prjtrellis |
| openFPGALoader | https://github.com/trabucayre/openFPGALoader |
| luma.oled Python driver | https://luma-oled.readthedocs.io |
| LAN8720 datasheet | https://ww1.microchip.com/downloads/en/DeviceDoc/00002165B.pdf |
| iCE40 LP/HX family datasheet | `ICE/docs/iCE40LPHXFamilyDataSheet.pdf` (local) |
