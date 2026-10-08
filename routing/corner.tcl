# Timing repair at the fast corner (hold) or the slow corner (setup) on global routes, in a session of its own as in
# signoff STA: one session with several corners gives the clocks forwarded through the pads one latency.
source config.tcl
set corner $::env(CORNER)
load grt $corner
set_propagated_clock [all_clocks]

set_routing_layers -signal met1-met5 -clock met1-met5
global_route
estimate_parasitics -global_routing
if {$corner eq "ff"} {
  repair_timing -hold -hold_margin 0.1
} else {
  repair_timing -setup -setup_margin 0.15
}
write_db $out/grt.odb
