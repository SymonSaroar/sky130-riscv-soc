source config.tcl
load floorplan

# the bond pad nets and the pads' own tie loops stay as they are
set_dont_touch [get_nets -of_objects [get_pins {*/PAD */TIE_HI_ESD */TIE_LO_ESD}]]

# the cell that drives an output pad starts at the core edge next to its pad and stays there through global
# placement, so pad paths and the clocks forwarded with them run short
set block [ord::get_db_block]
set core [$block getCoreArea]
set m [ord::microns_to_dbu 5]
set held {}
foreach pad [$block getInsts] {
  if {[[$pad getMaster] getName] ne "sky130_ef_io__gpiov2_pad_wrapped"} continue
  set net [[$pad findITerm OUT] getNet]
  if {$net eq "NULL"} continue
  foreach it [$net getITerms] {
    set drv [$it getInst]
    if {[$it getIoType] ne "OUTPUT" || [$drv getName] eq [$pad getName] ||
        [string match *conb* [[$drv getMaster] getName]] || [$drv getPlacementStatus] eq "FIRM"} continue
    set b [$pad getBBox]
    set w [[$drv getMaster] getWidth]
    set x [expr {min(max(([$b xMin] + [$b xMax]) / 2, [$core xMin] + $m), [$core xMax] - $m - $w)}]
    set y [expr {min(max(([$b yMin] + [$b yMax]) / 2, [$core yMin] + $m), [$core yMax] - $m - 2720)}]
    set x [expr {[$core xMin] + ($x - [$core xMin]) / 460 * 460}]
    set y [expr {[$core yMin] + ($y - [$core yMin]) / 2720 * 2720}]
    $drv setLocation $x $y
    $drv setPlacementStatus FIRM
    lappend held $drv
  }
}
global_placement -density $place_density -pad_left $gpl_pad -pad_right $gpl_pad
foreach drv $held { $drv setPlacementStatus PLACED }
# a tie cell next to every constant pin
repair_tie_fanout sky130_fd_sc_hd__conb_1/LO
repair_tie_fanout sky130_fd_sc_hd__conb_1/HI
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
repair_design -slew_margin 50 -cap_margin 10
detailed_placement
check_placement -verbose

report_stage place
write_db $out/place.odb
