# GSAF smoke test Makefile
# Run from tb/ directory: make SIM=verilator

SIM ?= verilator

COMPILE_ARGS += -I../rtl
ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing
endif

VERILOG_SOURCES = \
    ../rtl/gf_pkg.sv \
    ../rtl/gf_fifo.sv \
    ../rtl/gf_mont_mult.sv \
    ../rtl/gf_montgomery_cluster.sv \
    ../rtl/gf_modexp_engine.sv \
    ../rtl/gf_modinv_engine.sv \
    ../rtl/gf_pqc_engine.sv \
    ../rtl/gf_rsa_crt_engine.sv \
    ../rtl/gf_ecc_engine.sv \
    ../rtl/gf_modexp_engine_wrapper.sv \
    ../rtl/gf_modinv_engine_wrapper.sv \
    ../rtl/gf_pqc_engine_wrapper.sv \
    ../rtl/gf_rsa_crt_engine_wrapper.sv \
    ../rtl/gf_ecc_engine_wrapper.sv \
    ../rtl/gf_microcode_rom.sv \
    ../rtl/gf_operand_banks.sv \
    ../rtl/gf_transaction_table.sv \
    ../rtl/gf_scheduler.sv \
    ../rtl/gf_completion_queue.sv \
    ../rtl/gf_reorder_buffer.sv \
    ../rtl/gf_axil_frontend.sv \
    ../rtl/gf_secure_fabric_top.sv

TOPLEVEL = gf_secure_fabric_top
MODULE = test_gsaf_smoke

COCOTB_MAKEFILES = $(shell cocotb-config --makefiles 2>/dev/null || python3 -c "import cocotb,os;p=os.path.join(os.path.dirname(cocotb.__file__),'share');print(p if os.path.exists(os.path.join(p,'Makefile.sim')) else os.path.join(p,'makefiles'))")

include $(COCOTB_MAKEFILES)/Makefile.sim
