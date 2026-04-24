# Simulation Makefile – iCESugar-Pro Network Tap
# Requires: iverilog, gtkwave (optional)
#
# Targets:
#   make bridge      – unit test: phy_bridge (forwarding + MITM)
#   make smi         – unit test: smi_slave (register read/write)
#   make top         – full system simulation
#   make all         – run all three
#   make wave TB=... – open waveform for a specific TB in GTKWave
#   make clean       – remove build artefacts

IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

SRCS_COMMON = \
    ../../lib/cdc_sync.v    \
    ../../lib/rmii_rx.v     \
    ../../lib/rmii_tx.v     \
    ../../lib/async_fifo.v  \
    src/phy_bridge.v     \
    src/smi_slave.v

SRCS_TOP = $(SRCS_COMMON) src/top.v

IFLAGS = -Wall -Wno-timescale -g2005

.PHONY: all bridge smi top wave clean

all: bridge smi top

# ------------------------------------------------------------------
bridge: sim/tb_phy_bridge.vvp
	$(VVP) $<

sim/tb_phy_bridge.vvp: $(SRCS_COMMON) tb/tb_phy_bridge.v | sim/
	$(IVERILOG) $(IFLAGS) -o $@ $(SRCS_COMMON) tb/tb_phy_bridge.v

# ------------------------------------------------------------------
smi: sim/tb_smi_slave.vvp
	$(VVP) $<

sim/tb_smi_slave.vvp: src/smi_slave.v tb/tb_smi_slave.v | sim/
	$(IVERILOG) $(IFLAGS) -o $@ src/smi_slave.v tb/tb_smi_slave.v

# ------------------------------------------------------------------
top: sim/tb_top.vvp
	$(VVP) $<

sim/tb_top.vvp: $(SRCS_TOP) tb/tb_top.v | sim/
	$(IVERILOG) $(IFLAGS) -o $@ $(SRCS_TOP) tb/tb_top.v

# ------------------------------------------------------------------
wave:
	$(GTKWAVE) sim/$(TB).vcd &

sim/:
	mkdir -p sim

clean:
	rm -rf sim/
