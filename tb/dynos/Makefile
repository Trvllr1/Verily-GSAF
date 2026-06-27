# Dyno test Makefile — runs engine-only cocotb tests
# Run from tb/dynos/ directory: make test-pqc SIM=verilator

SIM ?= verilator

COMPILE_ARGS = -I../../rtl -DSIMULATION
ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing
endif

RTL_DIR = ../../rtl

COCOTB_MAKEFILES = $(shell cocotb-config --makefiles 2>/dev/null || python3 -c "import cocotb,os;p=os.path.join(os.path.dirname(cocotb.__file__),'share');print(p if os.path.exists(os.path.join(p,'Makefile.sim')) else os.path.join(p,'makefiles'))")

export COMPILE_ARGS

.PHONY: test-modexp test-modinv test-pqc test-rsa-crt test-ecc test-all clean

test-ecc:
	MODULE=dyno_ecc TOPLEVEL=tb_dyno_ecc SIM=$(SIM) \
	VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_ecc_engine.sv $(RTL_DIR)/gf_ecc_engine_wrapper.sv tb_dyno_ecc.sv" \
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim sim

test-pqc:
	MODULE=dyno_pqc TOPLEVEL=tb_dyno_pqc SIM=$(SIM) \
	VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_pqc_engine.sv $(RTL_DIR)/gf_pqc_engine_wrapper.sv tb_dyno_pqc.sv" \
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim sim

test-modexp:
	MODULE=dyno_modexp TOPLEVEL=tb_dyno_modexp SIM=$(SIM) \
	VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_modexp_engine.sv $(RTL_DIR)/gf_modexp_engine_wrapper.sv tb_dyno_modexp.sv" \
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim sim

test-modinv:
	MODULE=dyno_modinv TOPLEVEL=tb_dyno_modinv SIM=$(SIM) \
	VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_modinv_engine.sv $(RTL_DIR)/gf_modinv_engine_wrapper.sv tb_dyno_modinv.sv" \
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim sim

test-rsa-crt:
	MODULE=dyno_rsa_crt TOPLEVEL=tb_dyno_rsa_crt SIM=$(SIM) \
	VERILOG_SOURCES="$(RTL_DIR)/gf_pkg.sv $(RTL_DIR)/gf_mont_mult.sv $(RTL_DIR)/gf_montgomery_cluster.sv $(RTL_DIR)/gf_rsa_crt_engine.sv $(RTL_DIR)/gf_rsa_crt_engine_wrapper.sv tb_dyno_rsa_crt.sv" \
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim sim

test-all: test-modexp test-modinv test-pqc test-rsa-crt test-ecc

clean:
	rm -rf sim_build results.xml __pycache__
