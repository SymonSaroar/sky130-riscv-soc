source config.tcl
load cts
set_propagated_clock [all_clocks]

set_routing_layers -signal met1-met5 -clock met1-met5
global_route -congestion_report_file $rep/congestion.rpt
estimate_parasitics -global_routing
repair_design -slew_margin 10 -cap_margin 10
repair_timing -setup -skip_buffering
repair_timing -hold -hold_margin 0.2
# slew and load once more on the gates timing repair cloned or resized, with 10% margin
repair_design -slew_margin 10 -cap_margin 10
global_route -start_incremental
detailed_placement
global_route -end_incremental -congestion_report_file $rep/congestion.rpt
estimate_parasitics -global_routing
report_stage grt
# antenna repair may add diodes on the SRAM pin nets
unset_dont_touch [get_nets net_u_*_mem_*]
repair_antennas sky130_fd_sc_hd__diode_2
detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
# antenna repair on the detailed routes; only changed nets are rerouted
for {set i 0} {$i < 4 && [check_antennas] > 0} {incr i} {
  repair_antennas sky130_fd_sc_hd__diode_2
  detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
}
write_db $out/droute.odb
