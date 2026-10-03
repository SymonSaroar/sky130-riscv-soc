source config.tcl
load droute
set_propagated_clock [all_clocks]
set_routing_layers -signal met1-met5 -clock met1-met5

# a buffer in front of every gate the diodes did not fix
if {[check_antennas -report_file $rep/antenna.rpt] > 0} {
  set pins {}
  set f [open $rep/antenna.rpt]
  foreach line [split [read $f] \n] {
    if {[regexp {^\s+Pin:\s+(\S+)} $line -> pin]} continue
    if {[string match *VIOLATED* $line] && [lsearch $pins $pin] < 0} { lappend pins $pin }
  }
  close $f
  global_route -start_incremental
  foreach p $pins {
    lassign [split $p /] inst term
    lassign [[[[ord::get_db_block] findInst $inst] findITerm $term] getAvgXY] ok x y
    insert_buffer -buffer_cell sky130_fd_sc_hd__buf_2 -load_pins $p \
      -buffer_name ant_buf_${inst}_$term -net_name ant_net_${inst}_$term \
      -location [list [ord::dbu_to_microns $x] [ord::dbu_to_microns $y]]
  }
  detailed_placement
  global_route -end_incremental
  detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
  # diodes on the nets the reroute changed
  for {set i 0} {$i < 4 && [check_antennas] > 0} {incr i} {
    repair_antennas sky130_fd_sc_hd__diode_2
    detailed_route -output_drc $rep/route_drc.rpt -droute_end_iter 64 -verbose 1
  }
}
# LibreLane's sky130 fill: the reduced-li decap_12, smaller decaps, then fill cells
filler_placement {sky130_ef_sc_hd__decap_12 sky130_fd_sc_hd__decap_8 sky130_fd_sc_hd__decap_6 sky130_fd_sc_hd__decap_4
                  sky130_fd_sc_hd__decap_3 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1}
global_connect
check_antennas -report_file $rep/antenna.rpt

# placement blockages are not needed past placement and Magic cannot read soft ones
foreach b [[ord::get_db_block] getBlockages] { odb::dbBlockage_destroy $b }

# gates and buffers named after a hierarchical net get '_' for '.'; flops, SRAMs and pads keep their names
foreach inst [[ord::get_db_block] getInsts] {
  set n [$inst getName]
  set m [[$inst getMaster] getName]
  if {[string first . $n] < 0 || ![string match sky130_fd_sc_hd__* $m] || [string match sky130_fd_sc_hd__df* $m]} continue
  set to [string map {. _} $n]
  while {[[ord::get_db_block] findInst $to] ne "NULL"} { append to _ }
  $inst rename $to
}

write_db $out/route.odb
write_def $out/chip_top.def
# the timing netlist leaves out the supply pads, corners, bus slices, and the fill, decap and tap cells
set no_timing {}
foreach lib [[ord::get_db] getLibs] {
  foreach m [$lib getMasters] {
    set n [$m getName]
    if {([string match sky130_ef_io__* $n] && $n ne "sky130_ef_io__gpiov2_pad_wrapped") ||
        [string match sky130_fd_sc_hd__fill_* $n] || [string match sky130_*_sc_hd__decap_* $n] ||
        $n eq "sky130_fd_sc_hd__tapvpwrvgnd_1"} {
      lappend no_timing $n
    }
  }
}
write_verilog -remove_cells $no_timing $out/chip_top.final.v
write_verilog -include_pwr_gnd $out/chip_top.pwr.v
