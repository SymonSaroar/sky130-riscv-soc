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
add_pdn_stripe -grid core -layer met4 -width 1.6 -pitch 153.6 -offset 16.32 -extend_to_core_ring
add_pdn_stripe -grid core -layer met5 -width 1.6 -pitch 153.18 -offset 16.65 -extend_to_core_ring
add_pdn_connect -grid core -layers {met1 met4}
add_pdn_connect -grid core -layers {met4 met5}

define_pdn_grid -macro -name sram -cells sky130_sram_2kbyte_1rw1r_32x512_8 -halo 5
add_pdn_connect -grid sram -layers {met4 met5}

pdngen

# Straps from the core-side met3 pins of the VCCD and VSSD pads to their ring.
# North and south: met4 straps, via3 on the pin, via4 on the met5 ring.
# East and west: met3 straps, via3 on the met4 ring.
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

set block [ord::get_db_block]
set tech  [[ord::get_db] getTech]
set via3  [$tech findVia M3M4_PR]
set via4  [$tech findVia M4M5_PR]
set core  [$block getCoreArea]
foreach {pat netname pin} {vccd_* VPWR VCCD vssd_* VGND VSSD} {
  set net  [$block findNet $netname]
  set sw   [odb::dbSWire_create $net ROUTED]
  set ring [ring_boxes $net]
  foreach inst [$block getInsts] {
    if {![string match $pat [$inst getName]]} continue
    set side [lindex [split [$inst getName] _] 1]
    set pb [$inst getBBox]
    foreach r [pad_rects $inst $pin met3] {
      lassign $r x0 y0 x1 y1
      # only the pins on the core side of the pad
      switch $side {
        south { if {$y1 < [$pb yMax]} continue }
        north { if {$y0 > [$pb yMin]} continue }
        west  { if {$x1 < [$pb xMax]} continue }
        east  { if {$x0 > [$pb xMin]} continue }
      }
      foreach b $ring {
        lassign $b l bx0 by0 bx1 by1
        if {$side in {south north} && ($bx0 > $x0 || $bx1 < $x1)} continue
        if {$side in {west east} && ($by0 > $y0 || $by1 < $y1)} continue
        switch $side {
          south { if {$l ne "met5" || $by1 > [$core yMin]} continue
                  odb::dbSBox_create $sw [$tech findLayer met4] $x0 $y0 $x1 $by1 STRIPE
                  via_array $sw $via3 $x0 $y0 $x1 $y1 0.8 0.4
                  via_array $sw $via4 $x0 $by0 $x1 $by1 1.6 0.8
                  break }
          north { if {$l ne "met5" || $by0 < [$core yMax]} continue
                  odb::dbSBox_create $sw [$tech findLayer met4] $x0 $by0 $x1 $y1 STRIPE
                  via_array $sw $via3 $x0 $y0 $x1 $y1 0.8 0.4
                  via_array $sw $via4 $x0 $by0 $x1 $by1 1.6 0.8
                  break }
          west  { if {$l ne "met4" || $bx1 > [$core xMin]} continue
                  odb::dbSBox_create $sw [$tech findLayer met3] $x0 $y0 $bx1 $y1 STRIPE
                  via_array $sw $via3 $bx0 $y0 $bx1 $y1 0.8 0.4
                  break }
          east  { if {$l ne "met4" || $bx0 < [$core xMax]} continue
                  odb::dbSBox_create $sw [$tech findLayer met3] $bx0 $y0 $x1 $y1 STRIPE
                  via_array $sw $via3 $bx0 $y0 $bx1 $y1 0.8 0.4
                  break }
        }
      }
    }
  }
}
