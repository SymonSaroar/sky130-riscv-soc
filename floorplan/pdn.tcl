# Core supply on VPWR/VGND; the pad ring buses keep their own nets
add_global_connection -net VPWR -pin_pattern {^(VPWR|VPB|vccd1|VCCD|VCCHIB)$} -power
add_global_connection -net VGND -pin_pattern {^(VGND|VNB|vssd1|VSSD)$} -ground
add_global_connection -net VDDIO -pin_pattern {^(VDDIO|VSWITCH)$} -power
add_global_connection -net VDDIO_Q -pin_pattern {^VDDIO_Q$} -power
add_global_connection -net VSSIO -pin_pattern {^VSSIO$} -ground
add_global_connection -net VSSIO_Q -pin_pattern {^VSSIO_Q$} -ground
add_global_connection -net VDDA -pin_pattern {^VDDA$} -power
add_global_connection -net VSSA -pin_pattern {^VSSA$} -ground
add_global_connection -net AMUXBUS_A -pin_pattern {^AMUXBUS_A$}
add_global_connection -net AMUXBUS_B -pin_pattern {^AMUXBUS_B$}
global_connect
# the analog buses run through the pads by abutment and are not routed
foreach n {AMUXBUS_A AMUXBUS_B} { [[ord::get_db_block] findNet $n] setSpecial }
set_voltage_domain -power VPWR -ground VGND

define_pdn_grid -name core
add_pdn_ring -grid core -layers {met4 met5} -widths 8 -spacings 2 -core_offsets 4
add_pdn_stripe -grid core -layer met1 -width 0.48 -followpins
add_pdn_stripe -grid core -layer met4 -width 3.2 -pitch 153.6 -offset 16.32 -extend_to_core_ring
add_pdn_stripe -grid core -layer met5 -width 3.2 -pitch 153.18 -offset 16.65 -extend_to_core_ring
add_pdn_connect -grid core -layers {met1 met4}
add_pdn_connect -grid core -layers {met4 met5}

define_pdn_grid -macro -name sram -cells sky130_sram_2kbyte_1rw1r_32x512_8 -halo 5
add_pdn_connect -grid sram -layers {met4 met5}

pdngen

# Straps from the core-side met3 pins of the VCCD and VSSD pads to their ring, on met3 all the way
# out of the pad. North and south: met4 landings inside the met5 ring, clear of other met4, with via3 and
# via4 arrays. East and west: via3 arrays onto the met4 ring.
proc xform {inst x y} {
  set m [$inst getMaster]
  set w [$m getWidth]
  set h [$m getHeight]
  lassign [$inst getLocation] lx ly
  switch [$inst getOrient] {
    R0   { list [expr {$lx + $x}]      [expr {$ly + $y}] }
    R90  { list [expr {$lx + $h - $y}] [expr {$ly + $x}] }
    R180 { list [expr {$lx + $w - $x}] [expr {$ly + $h - $y}] }
    R270 { list [expr {$lx + $y}]      [expr {$ly + $w - $x}] }
    MX   { list [expr {$lx + $x}]      [expr {$ly + $h - $y}] }
    MY   { list [expr {$lx + $w - $x}] [expr {$ly + $y}] }
  }
}

proc pad_rects {inst mterm layer} {
  set rects {}
  foreach mpin [[[$inst getMaster] findMTerm $mterm] getMPins] {
    foreach box [$mpin getGeometry] {
      if {[[$box getTechLayer] getName] ne $layer} continue
      lassign [xform $inst [$box xMin] [$box yMin]] ax ay
      lassign [xform $inst [$box xMax] [$box yMax]] bx by
      lappend rects [list [expr {min($ax, $bx)}] [expr {min($ay, $by)}] [expr {max($ax, $bx)}] [expr {max($ay, $by)}]]
    }
  }
  return $rects
}

# ring segments of a net: boxes longer than half the core on the ring layers, outside the core
proc ring_boxes {net} {
  set c [[ord::get_db_block] getCoreArea]
  set half [expr {([$c xMax] - [$c xMin]) / 2}]
  set boxes {}
  foreach sw [$net getSWires] {
    foreach b [$sw getWires] {
      if {[$b isVia]} continue
      set l [[$b getTechLayer] getName]
      if {$l ni {met4 met5}} continue
      if {[$b getDX] < $half && [$b getDY] < $half} continue
      if {[$b xMax] <= [$c xMin] || [$b xMin] >= [$c xMax] || [$b yMax] <= [$c yMin] || [$b yMin] >= [$c yMax]} {
        lappend boxes [list $l [$b xMin] [$b yMin] [$b xMax] [$b yMax]]
      }
    }
  }
  return $boxes
}

proc via_array {sw via x0 y0 x1 y1 pitch margin} {
  set p [ord::microns_to_dbu $pitch]
  set m [ord::microns_to_dbu $margin]
  for {set x [expr {$x0 + $m}]} {$x <= $x1 - $m} {incr x $p} {
    for {set y [expr {$y0 + $m}]} {$y <= $y1 - $m} {incr y $p} {
      odb::dbSBox_create $sw $via $x $y STRIPE
    }
  }
}

# x intervals of [x0, x1] left after removing other met4 shapes in the band y0..y1, with 1.6 um of room
proc clear_x {block x0 y0 x1 y1} {
  set m [ord::microns_to_dbu 1.6]
  set cuts {}
  foreach net [$block getNets] {
    if {![$net isSpecial]} continue
    foreach sw [$net getSWires] {
      foreach b [$sw getWires] {
        if {[$b isVia] || [[$b getTechLayer] getName] ne "met4"} continue
        if {[$b xMax] + $m <= $x0 || [$b xMin] - $m >= $x1 || [$b yMax] <= $y0 || [$b yMin] >= $y1} continue
        lappend cuts [list [expr {[$b xMin] - $m}] [expr {[$b xMax] + $m}]]
      }
    }
  }
  set free [list [list $x0 $x1]]
  foreach c [lsort -integer -index 0 $cuts] {
    lassign $c c0 c1
    set next {}
    foreach f $free {
      lassign $f f0 f1
      if {$c1 <= $f0 || $c0 >= $f1} { lappend next $f; continue }
      if {$c0 > $f0} { lappend next [list $f0 $c0] }
      if {$c1 < $f1} { lappend next [list $c1 $f1] }
    }
    set free $next
  }
  return $free
}

set block [ord::get_db_block]
set tech  [[ord::get_db] getTech]
set met3  [$tech findLayer met3]
set met4  [$tech findLayer met4]
set via3  [$tech findVia M3M4_PR]
set via4  [$tech findVia M4M5_PR]
set core  [$block getCoreArea]
set straps {}
foreach {pat netname pin} {vccd_* VPWR VCCD vssd_* VGND VSSD} {
  set net  [$block findNet $netname]
  set ring [ring_boxes $net]
  foreach inst [$block getInsts] {
    if {![string match $pat [$inst getName]]} continue
    set side [lindex [split [$inst getName] _] 1]
    set pb [$inst getBBox]
    set in [ord::microns_to_dbu 2]
    foreach r [pad_rects $inst $pin met3] {
      # edges on a 10 nm grid, inside the pin
      lassign [lmap v $r {expr {$v / 10 * 10}}] x0 y0 x1 y1
      set x0 [expr {$x0 + 10 * ($x0 != [lindex $r 0])}]
      set y0 [expr {$y0 + 10 * ($y0 != [lindex $r 1])}]
      # pins on the core side of the pad; the strap starts 2 um inside the pad edge
      switch $side {
        south { if {$y1 < [$pb yMax]} continue; set y0 [expr {[$pb yMax] - $in}] }
        north { if {$y0 > [$pb yMin]} continue; set y1 [expr {[$pb yMin] + $in}] }
        west  { if {$x1 < [$pb xMax]} continue; set x0 [expr {[$pb xMax] - $in}] }
        east  { if {$x0 > [$pb xMin]} continue; set x1 [expr {[$pb xMin] + $in}] }
      }
      foreach b $ring {
        lassign $b l bx0 by0 bx1 by1
        if {$side in {south north} && ($l ne "met5" || $bx0 > $x0 || $bx1 < $x1)} continue
        if {$side in {west east} && ($l ne "met4" || $by0 > $y0 || $by1 < $y1)} continue
        switch $side {
          south { if {$by1 > [$core yMin]} continue; lappend straps [list $net ns $x0 $y0 $x1 $by1 $by0 $by1] }
          north { if {$by0 < [$core yMax]} continue; lappend straps [list $net ns $x0 $by0 $x1 $y1 $by0 $by1] }
          west  { if {$bx1 > [$core xMin]} continue; lappend straps [list $net ew $x0 $y0 $bx1 $y1 $bx0 $bx1] }
          east  { if {$bx0 < [$core xMax]} continue; lappend straps [list $net ew $bx0 $y0 $x1 $y1 $bx0 $bx1] }
        }
        break
      }
    }
  }
}
# landings are cleared against the PDN as it stands, before any strap is drawn
set landings {}
foreach st $straps {
  lassign $st net dir sx0 sy0 sx1 sy1 r0 r1
  if {$dir eq "ns"} { lappend landings [clear_x $block $sx0 $r0 $sx1 $r1] } else { lappend landings {} }
}
foreach st $straps land $landings {
  lassign $st net dir sx0 sy0 sx1 sy1 r0 r1
  set sw [odb::dbSWire_create $net ROUTED]
  odb::dbSBox_create $sw $met3 $sx0 $sy0 $sx1 $sy1 STRIPE
  if {$dir eq "ew"} {
    via_array $sw $via3 $r0 $sy0 $r1 $sy1 0.8 0.4
    continue
  }
  foreach f $land {
    lassign [lmap v $f {expr {$v / 10 * 10}}] fx0 fx1
    set fx0 [expr {$fx0 + 10 * ($fx0 != [lindex $f 0])}]
    if {$fx1 - $fx0 < [ord::microns_to_dbu 3.2]} continue
    odb::dbSBox_create $sw $met4 $fx0 $r0 $fx1 $r1 STRIPE
    via_array $sw $via3 $fx0 $r0 $fx1 $r1 0.8 0.4
    via_array $sw $via4 $fx0 $r0 $fx1 $r1 1.6 0.8
  }
}
