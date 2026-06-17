# =============================================================================
# GSAF Vivado Synthesis Script
# Copyright (c) 2026 Verily. All rights reserved.
#
# Usage:
#   vivado -mode batch -source fpga/synth-vivado.tcl -tclargs <part>
#   vivado -mode batch -source fpga/synth-vivado.tcl -tclargs xc7a35tcpg236-1
# =============================================================================

# Parse arguments
set part [lindex $argv 0]
if {$part eq ""} {
    set part "xc7a35tcpg236-1"
    puts "Using default part: $part"
}

# Project settings
set project_name "gsaf_fpga"
set output_dir "fpga/output"
file mkdir $output_dir

# Create project
create_project $project_name $output_dir/$project_name -part $part -force

# Read RTL files
set rtl_files {
    rtl/gf_pkg.sv
    rtl/gf_fifo.sv
    rtl/gf_mont_mult.sv
    rtl/gf_montgomery_cluster.sv
    rtl/gf_modexp_engine.sv
    rtl/gf_modinv_engine.sv
    rtl/gf_pqc_engine.sv
    rtl/gf_microcode_rom.sv
    rtl/gf_operand_banks.sv
    rtl/gf_transaction_table.sv
    rtl/gf_scheduler.sv
    rtl/gf_completion_queue.sv
    rtl/gf_reorder_buffer.sv
    rtl/gf_axil_frontend.sv
    rtl/gf_secure_fabric_top.sv
}

foreach file $rtl_files {
    if {[file exists $file]} {
        read_verilog -sv $file
        puts "Read: $file"
    } else {
        puts "WARNING: File not found: $file"
    }
}

# Read constraints (if they exist)
set constraint_file "fpga/constraints/[file rootname [file tail $part]].xdc"
if {[file exists $constraint_file]} {
    read_xdc $constraint_file
    puts "Read constraints: $constraint_file"
} else {
    puts "WARNING: No constraints file found for $part"
}

# Set top module
set_top gf_secure_fabric_top

# Synthesis
puts "\n=== Running Synthesis ==="
synth_design -top gf_secure_fabric_top -part $part
report_utilization -file $output_dir/utilization_synth.rpt
report_timing_summary -file $output_dir/timing_synth.rpt

# Optimization
puts "\n=== Running Optimization ==="
opt_design

# Placement
puts "\n=== Running Placement ==="
place_design
report_utilization -file $output_dir/utilization_placed.rpt
report_timing_summary -file $output_dir/timing_placed.rpt

# Routing
puts "\n=== Running Routing ==="
route_design
report_utilization -file $output_dir/utilization_routed.rpt
report_timing_summary -file $output_dir/timing_routed.rpt
report_drc -file $output_dir/drc_routed.rpt

# Generate bitstream
puts "\n=== Generating Bitstream ==="
write_bitstream -force $output_dir/gsaf.bit

# Generate report
puts "\n=== Synthesis Complete ==="
puts "Bitstream: $output_dir/gsaf.bit"
puts "Reports:   $output_dir/*.rpt"
