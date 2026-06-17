// GSAF compile order (pass to simulator with -f sim/gsaf.f)
+incdir+rtl
+incdir+tb
rtl/gf_pkg.sv
rtl/gf_fifo.sv
rtl/gf_mont_mult.sv
rtl/gf_montgomery_cluster.sv
rtl/gf_modexp_engine.sv
rtl/gf_modinv_engine.sv
rtl/gf_microcode_rom.sv
rtl/gf_operand_banks.sv
rtl/gf_transaction_table.sv
rtl/gf_scheduler.sv
rtl/gf_completion_queue.sv
rtl/gf_reorder_buffer.sv
rtl/gf_axil_frontend.sv
rtl/gf_secure_fabric_top.sv
tb/tb_gsaf_smoke.sv
