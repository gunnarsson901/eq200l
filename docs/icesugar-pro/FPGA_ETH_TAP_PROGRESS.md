# FPGA Ethernet Tap — Development Log

## Hardware

- iCESugar Pro (LFE5U-25F-6CABGA256 ECP5) on BRB carrier board
- Two LAN8720 RMII PHY modules (ETH1 on P2 connector, ETH2 on P3 connector)
- Raspberry Pi 4 connected via SPI (capture readout) and JTAG (bitstream loading)

---

## Issue 1 — ETH2 pin row A/B swapped

**Symptom:** 0 frames captured from ETH2 after initial wiring.

**Root cause:** The 2×7 LAN8720 module connector has B-row pins (REFCLK, CRS_DV, RXD,
TXD) and A-row pins (MDC/MDIO, RXD, TXD). The initial LPF had every signal on the wrong
row — A↔B swapped throughout.

**Correct ETH2 pin mapping (P3 connector on BRB):**

| Signal    | FPGA site | LAN8720 pin |
|-----------|-----------|-------------|
| REFCLKO   | B7        | nINT/REFCLKO |
| CRS_DV    | A7        | CRS_DV      |
| RXD[0]    | B6        | RXD0        |
| RXD[1]    | A6        | RXD1        |
| TX_EN     | B5        | TXEN        |
| TXD[0]    | A5        | TXD0        |
| TXD[1]    | B4        | TXD1        |
| MDIO      | B8        | MDIO        |
| MDC       | A8        | MDC         |

**Fix:** Updated `ICE/icesugar-pro/hw/top.lpf` with the correct LOCATE COMP entries.

**Verification:** After the fix we got 2 legible frames showing `ff:ff:ff:ff:ff:ff`
broadcast destination — confirming the RX path was alive.

---

## Issue 2 — PLL left in top.v with e2_ref_clk as output

**Symptom:** After a context-compaction rebuild the FPGA had a PLL driving e2_ref_clk as an
*output*, but the LAN8720 XTS 50 MHz crystal is the clock *source* (REFCLKO on B7 drives the
FPGA).

**Root cause:** A previous edit had added an EHXPLLL block to generate 50 MHz, treating
e2_ref_clk as a PLL output. When the LAN8720 is in REFCLKO mode it drives B7; the FPGA
must accept this as an input, not drive it.

**Fix:**
- Removed the EHXPLLL block from `top.v`.
- Changed `output wire e2_ref_clk` → `input wire e2_ref_clk`.
- All ETH2 clock-domain logic now uses `e2_ref_clk` directly (no `clk_50m`).
- Changed `led_b` from `~pll_lock` to `~link_up[1]` (ETH2 link-down indicator).

---

## Issue 3 — LAN8720 CRS_DV demultiplexing causes preamble bytes in frame data

**Symptom:** Captured "frames" contained preamble bytes (0xAA/0x55 patterns) in the
payload, and the SFD (0xD5) was visible inside frame data.

**Root cause:** The LAN8720 demultiplexes CRS (Carrier Sense) and DV (Data Valid) onto the
single CRS_DV pin on *alternate* REFCLKO cycles:
- During preamble (before internal SFD detection): CRS=1, DV=0 → CRS_DV alternates 1/0/1/0
- After SFD detected internally: CRS=1, DV=1 → CRS_DV stays high

The original `rmii_rx` treated a single CRS_DV low as end-of-frame. During the preamble the
alternating lows bounced the state machine back to IDLE mid-preamble, causing it to
re-enter PREAMBLE at a wrong dibit offset. The resulting frame data was a mix of preamble
and real payload.

**Fix applied to `ICE/lib/rmii_rx.v`:**
1. Added `crs_dv_prev` register (one-cycle delayed CRS_DV).
2. Changed all "return to IDLE" checks from `!crs_dv` to `!crs_dv && !crs_dv_prev` — two
   consecutive lows required (real end-of-frame, not the alternating preamble glitch).
3. Removed the `crs_dv` guard from DATA-state dibit collection — collect on every cycle,
   since after the internal SFD CRS_DV is steady; guarding caused 0 frames.
4. Removed the `crs_dv &&` requirement from SFD detection (`rxd == 2'b11`) in PREAMBLE
   state — the LAN8720 may briefly glitch CRS_DV at the preamble→data boundary.

**Status as of last test:** 14 frames captured in 10 s, SOF markers present, data still
shows dibit-alignment artefacts (`3F 00 00 FC` repeating pattern when broadcast FFs expected).
The 2-bit shift is consistent with a 1-dibit SFD boundary error still present — under
active investigation.

---

## SPI capture protocol

The FPGA streams captured Ethernet bytes to the Pi over SPI0 (Mode 0, 500 kHz):

- `0xFF` — idle (cap FIFO empty)
- `0xFE` — start-of-frame marker (inserted by FPGA SPI framer)
- `<N data bytes>` — Ethernet frame content (no explicit end marker; next `0xFE` or `0xFF`
  implies end)

The Pi reads 256-byte bursts with manual CS on GPIO 24.

---

## Remaining work

- Fix the 1-dibit alignment issue in `rmii_rx`: the DATA state appears to collect one
  dibit too early or the SFD dibit (11) is being included in the first data byte.
  Candidate fix: after SFD detection, skip one additional dibit before starting collection,
  or verify the LAN8720 timing of when REFCLKO-aligned data starts relative to the 11 dibit.
- Verify clean frame decode with a known test packet (ARP request, ICMP ping).
- Write captured frames to PCAP file on the Pi for Wireshark analysis.
- Burn to SPI flash (`make upload`) once capture is stable.
