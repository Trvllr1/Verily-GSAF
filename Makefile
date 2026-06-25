# GSAF Makefile — build, lint, simulate, verify, document
# Run from MSYS2 MinGW64 shell: make <target>

# Tool paths (MSYS2 MinGW64)
VERILATOR  ?= verilator
IVERILOG   ?= iverilog
YOSYS      ?= yosys
SBY        ?= sby
PYTHON     ?= python
COCOTB     ?= python -m cocotb

# Directories
RTL_DIR    := rtl
TB_DIR     := tb
FV_DIR     := fv
SIM_DIR    := sim
MODEL_DIR  := model
DOCS_DIR   := docs
EVIDENCE_DIR := evidence-pack

# Compile filelist
F_FILE     := $(SIM_DIR)/gsaf.f

.PHONY: all check-tools lint sim formal vectors docs evidence clean help

all: lint sim

# ─── Tool verification ───────────────────────────────────────────────────────
check-tools:
	@echo "Checking toolchain..."
	@$(VERILATOR) --version
	@$(IVERILOG) -v 2>&1 | grep -i "icarus"
	@$(YOSYS) --version
	@$(SBY) --version
	@$(PYTHON) -c "import cocotb; print(f'cocotb {cocotb.__version__}')"
	@echo "All tools OK."

# ─── Lint ────────────────────────────────────────────────────────────────────
lint:
	$(VERILATOR) --lint-only -Wall -I$(RTL_DIR) -f $(F_FILE) \
		--top-module gf_secure_fabric_top 2>&1 | tee lint.log
	@echo "Lint complete. Check lint.log for details."

# ─── Simulation (cocotb + Verilator) ─────────────────────────────────────────
sim:
	cd $(TB_DIR) && $(MAKE) \
		SIM=verilator \
		VERILATOR_ROOT=$(shell $(VERILATOR) -V 2>&1 | grep VERILATOR_ROOT | awk '{print $$3}')

# ─── Formal verification (SymbiYosys) ────────────────────────────────────────
formal:
	$(SBY) -f formal/sby_fabric.sby
	@echo "Formal proof complete."

formal-engine:
	$(SBY) -f formal/sby_modexp_const.sby
	$(SBY) -f formal/sby_modinv_const.sby
	$(SBY) -f formal/sby_ecc_const.sby
	$(SBY) -f formal/sby_pqc_const.sby
	$(SBY) -f formal/sby_rsa_crt_const.sby
	@echo "Engine formal proofs complete."

# ─── Vector generation ───────────────────────────────────────────────────────
vectors:
	$(PYTHON) $(MODEL_DIR)/gen_vectors.py > $(TB_DIR)/tb_vectors.svh
	@echo "Vectors regenerated."

# ─── Golden model self-test ──────────────────────────────────────────────────
golden-test:
	$(PYTHON) $(MODEL_DIR)/golden_model.py
	$(PYTHON) $(MODEL_DIR)/pqc_ntt_model.py

# ─── Documentation ───────────────────────────────────────────────────────────
docs:
	cd $(DOCS_DIR) && mkdocs serve

docs-build:
	cd $(DOCS_DIR) && mkdocs build

# ─── Evidence pack generation ────────────────────────────────────────────────
evidence: golden-test lint sim formal vectors
	@echo "Generating evidence pack..."
	@mkdir -p $(EVIDENCE_DIR)/01_chassis/rtl
	@mkdir -p $(EVIDENCE_DIR)/01_chassis/formal/results
	@mkdir -p $(EVIDENCE_DIR)/01_chassis/simulation
	@mkdir -p $(EVIDENCE_DIR)/01_chassis/golden_model
	@cp $(RTL_DIR)/*.sv $(EVIDENCE_DIR)/01_chassis/rtl/
	@cp -r formal/results/* $(EVIDENCE_DIR)/01_chassis/formal/results/ 2>/dev/null || true
	@cp lint.log $(EVIDENCE_DIR)/01_chassis/simulation/ 2>/dev/null || true
	@$(PYTHON) $(MODEL_DIR)/golden_model.py > $(EVIDENCE_DIR)/01_chassis/golden_model/selftest_output.txt 2>&1
	@$(PYTHON) $(MODEL_DIR)/pqc_ntt_model.py >> $(EVIDENCE_DIR)/01_chassis/golden_model/selftest_output.txt 2>&1
	@echo "Evidence pack generated in $(EVIDENCE_DIR)/"

# ─── Clean ───────────────────────────────────────────────────────────────────
clean:
	rm -rf obj_dir
	rm -rf simv simv.daidir csrc ucli.key
	rm -rf *_sbys workdir
	rm -f lint.log
	rm -f results.xml
