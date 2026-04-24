DEVICE  = 25k
PACKAGE = CABGA256
SPEED   = 6

SRCS = \
    src/top.v \
    ../sim_tap/src/phy_bridge.v \
    ../../lib/rmii_rx.v \
    ../../lib/rmii_tx.v \
    ../../lib/async_fifo.v

BUILD = build

.PHONY: all synth pnr pack flash clean

all: $(BUILD)/top.bit

# Synthesis
$(BUILD)/synth.json: $(SRCS) | $(BUILD)/
	yosys -p "synth_ecp5 -top top -json $@" $(SRCS) 2>&1 | tee $(BUILD)/synth.log

# Place and route
$(BUILD)/routed.config: $(BUILD)/synth.json top.lpf | $(BUILD)/
	nextpnr-ecp5 \
	    --$(DEVICE) --package $(PACKAGE) --speed $(SPEED) \
	    --json $< --lpf top.lpf --textcfg $@ \
	    2>&1 | tee $(BUILD)/pnr.log

# Pack bitstream
$(BUILD)/top.bit: $(BUILD)/routed.config | $(BUILD)/
	ecppack $< $@

# Flash via iCELink (CMSIS-DAP)
flash: $(BUILD)/top.bit
	openFPGALoader --cable cmsisdap $(BUILD)/top.bit

$(BUILD)/:
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)/
