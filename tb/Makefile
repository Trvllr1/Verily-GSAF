# cocotb testbench Makefile for GSAF
# Run from tb/ directory: make SIM=verilator

PYTHON ?= python
COCOTB_CONFIG ?= cocotb-config

# Simulator selection
SIM ?= verilator

# Verilator settings
ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing
    COMPILE_ARGS += -DGF_ASSERTIONS
    COMPILE_ARGS += -f ../sim/gsaf.f
    TOPLEVEL_LANG = verilog
    VERILOG_SOURCES = $(shell cat ../sim/gsaf.f)
endif

# Icarus Verilog settings
ifeq ($(SIM),icarus)
    COMPILE_ARGS += -g2012
    COMPILE_ARGS += -DGF_ASSERTIONS
    COMPILE_ARGS += -f ../sim/gsaf.f
    TOPLEVEL_LANG = verilog
    VERILOG_SOURCES = $(shell cat ../sim/gsaf.f)
endif

# Test module
MODULE = test_gsaf_smoke

# Top-level
TOPLEVEL = gf_secure_fabric_top

# Parameters
TOPLEVEL_LANG = verilog

# Include paths
INCLUDE_DIRS = ../rtl ../tb

# cocotb makefile
include $(shell $(COCOTB_CONFIG) --makefiles)/Makefile.sim

.PHONY: test clean

test:
	$(MAKE) sim

clean:
	rm -rf sim_build results.xml __pycache__
