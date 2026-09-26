# Static IR drop on both supplies, sourced where the supply pad straps meet the ring.
source config.tcl
source power/grid.tcl
load route
set_propagated_clock [all_clocks]
read_spef $out/chip_top.nom.spef
quiet_pads
foreach {net v} {VPWR 1.8 VGND 0.0} {
  write_vsrc $net $v $out/vsrc_$net.csv
  set_pdnsim_net_voltage -net $net -voltage $v
  analyze_power_grid -net $net -vsrc $out/vsrc_$net.csv -voltage_file $out/ir_$net.csv -enable_em -em_outfile $out/em_$net.csv
}
