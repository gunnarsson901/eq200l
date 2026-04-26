DEVICE  = 25k
PACKAGE = CABGA256
SPEED   = 6

SRCS = \
    src/top.v \
    src/frame_uart.v \
    ../sim_tap/src/phy_bridge.v \
    ../../lib/rmii_rx.v \
    ../../lib/rmii_tx.v \
    ../../lib/async_fifo.v \
    ../../lib/bram_fifo.v \
    ../../lib/uart_tx.v

BUILD = build

.PHONY: all synth pnr pack program flash upload clean

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

# Flash via iCELink module USB-C (use module port, NOT the host-board port)
# icesprog requires VID:PID 0x1d50:0x602b (MuseLab firmware on module USB-C)
# Run directly on the Pi (no SSH)
program: $(BUILD)/top.bit
	icesprog -j 1 && icesprog -w $(BUILD)/top.bit

# Flash from laptop — assumes top.bit already on Pi at /tmp/top.bit
flash: $(BUILD)/top.bit
	ssh phoenix@192.168.10.238 "icesprog -j 1 && icesprog -w /tmp/top.bit"

# Upload from laptop — copies bitstream then flashes
upload: $(BUILD)/top.bit
	scp $(BUILD)/top.bit phoenix@192.168.10.238:/tmp/top.bit && \
	ssh phoenix@192.168.10.238 "icesprog -j 1 && icesprog -w /tmp/top.bit"

$(BUILD)/:
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)/
