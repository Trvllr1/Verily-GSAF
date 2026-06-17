# =============================================================================
# GSAF Artix-7 Constraints (xc7a35tcpg236-1)
# Copyright (c) 2026 Verily. All rights reserved.
#
# Pin assignments for Artix-7 evaluation board (Nexys A7 / Basys 3)
# =============================================================================

# Clock (100 MHz from on-board oscillator)
set_property PACKAGE_PIN E3 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
create_clock -period 10.000 -name clk_i -waveform {0.000 5.000} [get_ports clk_i]

# Reset (active low, directly from button)
set_property PACKAGE_PIN C12 [get_ports rst_ni]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ni]

# AXI4-Lite Interface (directly directly directly to PMOD header or external connector)
# AW Channel
set_property PACKAGE_PIN A3 [get_ports {s_axil_awaddr[0]}]
set_property PACKAGE_PIN B3 [get_ports {s_axil_awaddr[1]}]
set_property PACKAGE_PIN C3 [get_ports {s_axil_awaddr[2]}]
set_property PACKAGE_PIN C4 [get_ports {s_axil_awaddr[3]}]
set_property PACKAGE_PIN C5 [get_ports {s_axil_awaddr[4]}]
set_property PACKAGE_PIN D5 [get_ports {s_axil_awaddr[5]}]
set_property PACKAGE_PIN E5 [get_ports {s_axil_awaddr[6]}]
set_property PACKAGE_PIN F5 [get_ports {s_axil_awaddr[7]}]
set_property PACKAGE_PIN G5 [get_ports {s_axil_awaddr[8]}]
set_property PACKAGE_PIN H5 [get_ports {s_axil_awaddr[9]}]
set_property PACKAGE_PIN J5 [get_ports {s_axil_awaddr[10]}]
set_property PACKAGE_PIN K5 [get_ports {s_axil_awaddr[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {s_axil_awaddr[*]}]

set_property PACKAGE_PIN G4 [get_ports s_axil_awvalid]
set_property PACKAGE_PIN H4 [get_ports s_axil_awready]
set_property PACKAGE_PIN J4 [get_ports {s_axil_wdata[0]}]
set_property PACKAGE_PIN J3 [get_ports {s_axil_wdata[1]}]
set_property PACKAGE_PIN K3 [get_ports {s_axil_wdata[2]}]
set_property PACKAGE_PIN L3 [get_ports {s_axil_wdata[3]}]
set_property PACKAGE_PIN M3 [get_ports {s_axil_wdata[4]}]
set_property PACKAGE_PIN M4 [get_ports {s_axil_wdata[5]}]
set_property PACKAGE_PIN M5 [get_ports {s_axil_wdata[6]}]
set_property PACKAGE_PIN M6 [get_ports {s_axil_wdata[7]}]
set_property PACKAGE_PIN N6 [get_ports {s_axil_wdata[8]}]
set_property PACKAGE_PIN N8 [get_ports {s_axil_wdata[9]}]
set_property PACKAGE_PIN P8 [get_ports {s_axil_wdata[10]}]
set_property PACKAGE_PIN P9 [get_ports {s_axil_wdata[11]}]
set_property PACKAGE_PIN R9 [get_ports {s_axil_wdata[12]}]
set_property PACKAGE_PIN T9 [get_ports {s_axil_wdata[13]}]
set_property PACKAGE_PIN T10 [get_ports {s_axil_wdata[14]}]
set_property PACKAGE_PIN T11 [get_ports {s_axil_wdata[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {s_axil_wdata[*]}]

set_property PACKAGE_PIN V10 [get_ports s_axil_wvalid]
set_property PACKAGE_PIN V11 [get_ports s_axil_wready]
set_property PACKAGE_PIN V12 [get_ports s_axil_bvalid]
set_property PACKAGE_PIN V13 [get_ports s_axil_bready]
set_property PACKAGE_PIN V14 [get_ports {s_axil_bresp[0]}]
set_property PACKAGE_PIN T14 [get_ports {s_axil_bresp[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports s_axil_b*]

# AR Channel
set_property PACKAGE_PIN T15 [get_ports {s_axil_araddr[0]}]
set_property PACKAGE_PIN T16 [get_ports {s_axil_araddr[1]}]
set_property PACKAGE_PIN U16 [get_ports {s_axil_araddr[2]}]
set_property PACKAGE_PIN V15 [get_ports {s_axil_araddr[3]}]
set_property PACKAGE_PIN V16 [get_ports {s_axil_araddr[4]}]
set_property PACKAGE_PIN T13 [get_ports {s_axil_araddr[5]}]
set_property PACKAGE_PIN T12 [get_ports {s_axil_araddr[6]}]
set_property PACKAGE_PIN U12 [get_ports {s_axil_araddr[7]}]
set_property PACKAGE_PIN U11 [get_ports {s_axil_araddr[8]}]
set_property PACKAGE_PIN V11 [get_ports {s_axil_araddr[9]}]
set_property PACKAGE_PIN T11 [get_ports {s_axil_araddr[10]}]
set_property PACKAGE_PIN U10 [get_ports {s_axil_araddr[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {s_axil_araddr[*]}]

set_property PACKAGE_PIN V10 [get_ports s_axil_arvalid]
set_property PACKAGE_PIN V11 [get_ports s_axil_arready]

# R Channel
set_property PACKAGE_PIN V12 [get_ports {s_axil_rdata[0]}]
set_property PACKAGE_PIN V13 [get_ports {s_axil_rdata[1]}]
set_property PACKAGE_PIN V14 [get_ports {s_axil_rdata[2]}]
set_property PACKAGE_PIN T14 [get_ports {s_axil_rdata[3]}]
set_property PACKAGE_PIN T15 [get_ports {s_axil_rdata[4]}]
set_property PACKAGE_PIN T16 [get_ports {s_axil_rdata[5]}]
set_property PACKAGE_PIN U16 [get_ports {s_axil_rdata[6]}]
set_property PACKAGE_PIN V15 [get_ports {s_axil_rdata[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {s_axil_rdata[*]}]

set_property PACKAGE_PIN V16 [get_ports s_axil_rvalid]
set_property PACKAGE_PIN T13 [get_ports s_axil_rready]

# IRQ output (active high)
set_property PACKAGE_PIN U18 [get_ports irq_o]
set_property IOSTANDARD LVCMOS33 [get_ports irq_o]

# Idle output
set_property PACKAGE_PIN U17 [get_ports idle_o]
set_property IOSTANDARD LVCMOS33 [get_ports idle_o]

# Timing constraints
set_max_delay -from [get_cells u_frontend/*] -to [get_cells u_scheduler/*] 8.000
set_max_delay -from [get_cells u_scheduler/*] -to [get_cells u_frontend/*] 8.000
