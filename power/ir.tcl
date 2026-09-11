# Static IR drop on both supplies, sourced where the supply pad straps meet the ring.
source config.tcl
load route
set_propagated_clock [all_clocks]
read_spef $out/chip_top.nom.spef
set block [ord::get_db_block]
set c [$block getCoreArea]
foreach {net v} {VPWR 1.8 VGND 0.0} {
  set f [open $out/vsrc_$net.csv w]
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
  set_pdnsim_net_voltage -net $net -voltage $v
  analyze_power_grid -net $net -vsrc $out/vsrc_$net.csv -voltage_file $out/ir_$net.csv
}
