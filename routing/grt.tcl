source config.tcl
load cts
set_propagated_clock [all_clocks]

set_routing_layers -signal met1-met5 -clock met1-met5
global_route -congestion_report_file $rep/congestion.rpt
estimate_parasitics -global_routing
repair_design -slew_margin 50 -cap_margin 10
repair_timing -setup
repair_timing -hold -hold_margin 0.1
write_db $out/grt.odb
