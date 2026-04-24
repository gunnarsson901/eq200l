# Simulation Makefile — iCE40HX8K-EVB
# Requires: iverilog, gtkwave (optional)
#
# Targets:
#   make sim        - compile & run (default)
#   make wave       - open waveform in GTKWave
#   make clean      - remove build artefacts

# Number of 100 MHz clock cycles to simulate.
# 200 = quick sanity check; set higher for blink (100_000_000+ per toggle)
SIM_CYCLES ?= 200

TOP        = tb_top
SRCS       = src/top.v tb/tb_top.v
OUT        = sim/$(TOP).vvp
WAVES      = sim/waves.vcd

.PHONY: sim wave clean

sim: $(OUT)
	vvp $(OUT)

$(OUT): $(SRCS)
	@mkdir -p sim
	iverilog -Wall \
	         -DSIM_CYCLES=$(SIM_CYCLES) \
	         -o $(OUT) \
	         $(SRCS)

wave: $(WAVES)
	gtkwave $(WAVES) &

$(WAVES): sim

clean:
	rm -rf sim/
