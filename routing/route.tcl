source config.tcl
load cts
set_propagated_clock [all_clocks]

set_routing_layers -signal met1-met5 -clock met1-met5
global_route -congestion_report_file $rep/congestion.rpt
estimate_parasitics -global_routing
repair_design
repair_timing -setup
repair_timing -hold
global_route -start_incremental
detailed_placement
global_route -end_incremental -congestion_report_file $rep/congestion.rpt
estimate_parasitics -global_routing
report_stage grt
repair_antennas sky130_fd_sc_hd__diode_2
detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
# antenna repair on the detailed routes; only changed nets are rerouted
for {set i 0} {$i < 12 && [check_antennas] > 0} {incr i} {
  repair_antennas sky130_fd_sc_hd__diode_2
  detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
}
filler_placement {sky130_fd_sc_hd__decap_12 sky130_fd_sc_hd__decap_8 sky130_fd_sc_hd__decap_6 \
                  sky130_fd_sc_hd__decap_4 sky130_fd_sc_hd__decap_3 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1}
global_connect
check_antennas -report_file $rep/antenna.rpt

# placement blockages are not needed past placement and Magic cannot read soft ones
foreach b [[ord::get_db_block] getBlockages] { odb::dbBlockage_destroy $b }

write_db $out/route.odb
write_def $out/soc_top.def
write_verilog $out/soc_top.final.v
write_verilog -include_pwr_gnd $out/soc_top.pwr.v
