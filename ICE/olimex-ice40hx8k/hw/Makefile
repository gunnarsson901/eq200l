# =============================================================================
# Synthesis Makefile — iCE40HX8K LAN8720 RMII receiver
# Requires: yosys, nextpnr-ice40, icepack, iceprog (or icezero/iCEburn)
# =============================================================================
# Usage:
#   make          — synthesise + place-and-route + pack → top.bin
#   make upload   — also program via iceprog (FPGA on USB)
#   make clean    — remove all build outputs

DEVICE  ?= hx8k
PACKAGE ?= ct256

TOP     = top
PCF     = top.pcf
SRCS    = src/top.v \
          src/frame_store.v \
          src/frame_bram.v \
          ../../lib/rmii_rx.v \
          ../../lib/sync_fifo.v \
          ../../lib/spi_slave.v

BUILD   = build

.PHONY: all synth pnr pack upload freq_test clean

all: $(BUILD)/$(TOP).bin

# ------------------------------------------------------------------
# 1. Synthesis (Yosys → BLIF)
# ------------------------------------------------------------------
synth: $(BUILD)/$(TOP).json

$(BUILD)/$(TOP).json: $(SRCS) | $(BUILD)
	yosys -p "synth_ice40 -top $(TOP) -json $@" $(SRCS)

# ------------------------------------------------------------------
# 2. Place and route (nextpnr-ice40 → ASC)
# ------------------------------------------------------------------
pnr: $(BUILD)/$(TOP).asc

$(BUILD)/$(TOP).asc: $(BUILD)/$(TOP).json $(PCF)
	nextpnr-ice40 \
	    --$(DEVICE) \
	    --package $(PACKAGE) \
	    --json $< \
	    --pcf $(PCF) \
	    --asc $@

# ------------------------------------------------------------------
# 3. Bitstream pack (icepack → BIN)
# ------------------------------------------------------------------
pack: $(BUILD)/$(TOP).bin

$(BUILD)/$(TOP).bin: $(BUILD)/$(TOP).asc
	icepack $< $@

# ------------------------------------------------------------------
# 4. Upload via iceprog (FPGA connected to local USB)
# ------------------------------------------------------------------
upload: $(BUILD)/$(TOP).bin
	iceprog $<

# ------------------------------------------------------------------
# Frequency test — 6 divided clocks on pi03_07..pi03_12
# ------------------------------------------------------------------
FREQ_PCF  = freq_test.pcf
FREQ_SRCS = src/freq_test.v

freq_test: $(BUILD)/freq_test.bin

$(BUILD)/freq_test.json: $(FREQ_SRCS) | $(BUILD)
	yosys -p "synth_ice40 -top freq_test -json $@" $(FREQ_SRCS)

$(BUILD)/freq_test.asc: $(BUILD)/freq_test.json $(FREQ_PCF)
	nextpnr-ice40 \
	    --$(DEVICE) \
	    --package $(PACKAGE) \
	    --json $< \
	    --pcf $(FREQ_PCF) \
	    --asc $@

$(BUILD)/freq_test.bin: $(BUILD)/freq_test.asc
	icepack $< $@

# ------------------------------------------------------------------
$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
