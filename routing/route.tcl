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
for {set i 0} {$i < 4 && [check_antennas] > 0} {incr i} {
  repair_antennas sky130_fd_sc_hd__diode_2
  detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
}
write_db $out/droute.odb
