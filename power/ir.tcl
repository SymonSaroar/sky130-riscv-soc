# Static IR drop on both supplies, sources at the met5 power pins.
source config.tcl
load route
set_propagated_clock [all_clocks]
read_spef $out/chip_top.spef
foreach {net v} {VPWR 1.8 VGND 0.0} {
  set_pdnsim_net_voltage -net $net -voltage $v
  analyze_power_grid -net $net -source_type FULL -voltage_file $out/ir_$net.csv
}
