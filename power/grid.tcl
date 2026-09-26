# Core supply setup shared by decap insertion and IR drop.

# pad cells switch from VDDIO, so pads and data inputs carry no activity here; the clock pads still feed their trees
proc quiet_pads {} {
  set data_in [lmap p [all_inputs -no_clocks] {get_full_name $p}]
  set keep {}
  foreach p [all_inputs] {
    if {[get_full_name $p] ni $data_in} { lappend keep p_[get_full_name $p].p/IN }
  }
  set pins {}
  foreach p [get_pins -of_objects [get_cells -filter "ref_name == sky130_ef_io__gpiov2_pad_wrapped" *]] {
    if {[get_full_name $p] ni $keep} { lappend pins $p }
  }
  set_power_activity -input_ports [all_inputs -no_clocks] -density 0 -duty 0.5
  set_power_activity -pins $pins -density 0 -duty 0.5
}

# voltage sources where the supply pad straps meet the ring
proc write_vsrc {net v file} {
  set block [ord::get_db_block]
  set c [$block getCoreArea]
  set f [open $file w]
  foreach sw [[$block findNet $net] getSWires] {
    foreach b [$sw getWires] {
      if {[$b isVia] || [[$b getTechLayer] getName] ne "met3"} continue
      set x0 [ord::dbu_to_microns [$b xMin]]; set x1 [ord::dbu_to_microns [$b xMax]]
      set y0 [ord::dbu_to_microns [$b yMin]]; set y1 [ord::dbu_to_microns [$b yMax]]
      # a strap runs from its pad to the far edge of its ring, 4 um past the ring centre
      if {[$b yMax] < [$c yMin]} {
        puts $f "[expr {($x0 + $x1) / 2}],[expr {$y1 - 4}],8,$v"
      } elseif {[$b yMin] > [$c yMax]} {
        puts $f "[expr {($x0 + $x1) / 2}],[expr {$y0 + 4}],8,$v"
      } elseif {[$b xMax] < [$c xMin]} {
        puts $f "[expr {$x1 - 4}],[expr {($y0 + $y1) / 2}],8,$v"
      } elseif {[$b xMin] > [$c xMax]} {
        puts $f "[expr {$x0 + 4}],[expr {($y0 + $y1) / 2}],8,$v"
      }
    }
  }
  close $f
}
