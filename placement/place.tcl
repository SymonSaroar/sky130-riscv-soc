source config.tcl
load floorplan

global_placement -density $place_density -pad_left $gpl_pad -pad_right $gpl_pad
# A buffer next to every SRAM signal pin. The SRAM liberty limits input slew to 40 ps and
# output load to 0.0276 pF; the short pin-to-buffer nets stay out of repair.
foreach sram [[ord::get_db_block] getInsts] {
  if {![string match sky130_sram* [[$sram getMaster] getName]]} continue
  set inst [$sram getName]
  foreach it [$sram getITerms] {
    set name [[$it getMTerm] getName]
    if {[$it getSigType] ne "SIGNAL" || [string match clk* $name] || [$it getNet] eq "NULL"} { continue }
    lassign [$it getAvgXY] ok x y
    set tag [string map {[ _ ] {} . _ / _} $inst/$name]
    set at [list [ord::dbu_to_microns $x] [ord::dbu_to_microns $y]]
    if {[$it getIoType] eq "INPUT"} {
      insert_buffer -buffer_cell sky130_fd_sc_hd__buf_4 -load_pins $inst/$name \
        -buffer_name buf_$tag -net_name net_$tag -location $at
    } else {
      insert_buffer -buffer_cell sky130_fd_sc_hd__buf_4 -net [[$it getNet] getName] \
        -buffer_name buf_$tag -net_name net_$tag -location $at
    }
    set_dont_touch [get_nets -of_objects [get_pins $inst/$name]]
  }
}

estimate_parasitics -placement
repair_design
detailed_placement
check_placement -verbose

report_stage place
write_db $out/place.odb
