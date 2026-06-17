# Dyno test Makefile — runs engine-only cocotb tests
# Run from tb/dynos/ directory: make SIM=verilator

SIM ?= verilator

# Source files (relative to this directory)
RTL_DIR    = ../../rtl
SIM_DIR    = ../../sim

VERILOG_SOURCES = \
    $(RTL_DIR)/gf_pkg.sv \
    $(RTL_DIR)/gf_fifo.sv \
    $(RTL_DIR)/gf_mont_mult.sv \
    $(RTL_DIR)/gf_montgomery_cluster.sv \
    $(RTL_DIR)/gf_modexp_engine.sv \
    $(RTL_DIR)/gf_modinv_engine.sv \
    $(RTL_DIR)/gf_modexp_engine_wrapper.sv \
    $(RTL_DIR)/gf_modinv_engine_wrapper.sv \
    tb_dyno_modexp.sv \
    tb_dyno_modinv.sv

# Top-level (for compilation — cocotb overrides this per test)
TOPLEVEL = tb_dyno_modexp

# cocotb makefile
include $(shell python -c "import cocotb; print(cocotb.__file__.replace('__init__.py', 'share/cocotb/Makefile'))")

.PHONY: test-modexp test-modinv test-all clean

test-modexp:
	$(MAKE) sim MODULE=dyno_modexp TOPLEVEL=tb_dyno_modexp \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_modexp_engine.sv $(RTL_DIR)/gf_modexp_engine_wrapper.sv tb_dyno_modexp.sv"

test-modinv:
	$(MAKE) sim MODULE=dyno_modinv TOPLEVEL=tb_dyno_modinv \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_modexp_engine.sv $(RTL_DIR)/gf_modinv_engine.sv $(RTL_DIR)/gf_modinv_engine_wrapper.sv tb_dyno_modinv.sv"

test-all: test-modexp test-modinv

clean:
	rm -rf sim_build results.xml __pycache__
