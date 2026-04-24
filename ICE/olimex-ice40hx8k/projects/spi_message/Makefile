DEVICE  ?= hx8k
PACKAGE ?= ct256

TOP   = top
PCF   = top.pcf
SRCS  = src/top.v ../../../lib/spi_slave.v
BUILD = build

.PHONY: all clean

all: $(BUILD)/$(TOP).bin

$(BUILD)/$(TOP).json: $(SRCS) | $(BUILD)
	yosys -p "synth_ice40 -top $(TOP) -json $@" $(SRCS)

$(BUILD)/$(TOP).asc: $(BUILD)/$(TOP).json $(PCF)
	nextpnr-ice40 \
	    --$(DEVICE) \
	    --package $(PACKAGE) \
	    --json $< \
	    --pcf $(PCF) \
	    --asc $@

$(BUILD)/$(TOP).bin: $(BUILD)/$(TOP).asc
	icepack $< $@

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
