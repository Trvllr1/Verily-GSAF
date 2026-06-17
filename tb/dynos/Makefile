# Dyno test Makefile — runs engine-only cocotb tests
# Run from tb/dynos/ directory: make SIM=verilator
#
# Windows note: cocotb's cocotbvpi_verilator DLL is not shipped for Windows.
# Use WSL2 or Linux for simulation. See scripts/setup_sim.sh.

SIM ?= verilator
COMPILE_ARGS += -I../../rtl
ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing
endif

PYTHON ?= python
COCOTB_CONFIG ?= cocotb-config

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
include $(shell $(COCOTB_CONFIG) --makefiles)/Makefile.sim

.PHONY: test-modexp test-modinv test-pqc test-rsa-crt test-ecc test-all clean check-vpi

# Check if cocotbvpi_verilator DLL exists (needed for Verilator on Windows)
check-vpi:
	@if ! [ -f "$(shell $(PYTHON) -c "import cocotb,os; print(os.path.join(os.path.dirname(cocotb.__file__),'libs','cocotbvpi_verilator.dll').replace(chr(92),'/'))")" ]; then \
		echo "ERROR: cocotbvpi_verilator.dll not found."; \
		echo "cocotb does not ship this DLL for Windows. Use WSL2 or Linux."; \
		echo "See: scripts/setup_sim.sh"; \
		exit 1; \
	fi

test-modexp: check-vpi
	$(MAKE) sim MODULE=dyno_modexp TOPLEVEL=tb_dyno_modexp \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_modexp_engine.sv $(RTL_DIR)/gf_modexp_engine_wrapper.sv tb_dyno_modexp.sv"

test-modinv: check-vpi
	$(MAKE) sim MODULE=dyno_modinv TOPLEVEL=tb_dyno_modinv \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_modexp_engine.sv $(RTL_DIR)/gf_modinv_engine.sv $(RTL_DIR)/gf_modinv_engine_wrapper.sv tb_dyno_modinv.sv"

test-pqc: check-vpi
	$(MAKE) sim MODULE=dyno_pqc TOPLEVEL=tb_dyno_pqc \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_pqc_engine.sv $(RTL_DIR)/gf_pqc_engine_wrapper.sv tb_dyno_pqc.sv"

test-rsa-crt: check-vpi
	$(MAKE) sim MODULE=dyno_rsa_crt TOPLEVEL=tb_dyno_rsa_crt \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_rsa_crt_engine.sv $(RTL_DIR)/gf_rsa_crt_engine_wrapper.sv tb_dyno_rsa_crt.sv"

test-ecc: check-vpi
	$(MAKE) sim MODULE=dyno_ecc TOPLEVEL=tb_dyno_ecc \
		VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_fifo.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_ecc_engine.sv $(RTL_DIR)/gf_ecc_engine_wrapper.sv tb_dyno_ecc.sv"

test-all: test-modexp test-modinv test-pqc test-rsa-crt test-ecc
