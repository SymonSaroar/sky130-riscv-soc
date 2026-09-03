# Pad ring: four corners, each side's pads in order, bus slices in the gaps.
# Signal pads are netlist instances p_<name>.p; vccd, vssd, vddio, vssio, vdda, vssa add a supply pad,
# conn a slice that ties VCCHIB to VCCD and VSWITCH to VDDIO.
# Sides are listed in coordinate order: south and north left to right, west and east bottom to top.
set row(south) {conn vssio sdram_a0 sdram_a1 sdram_a2 vccd sdram_a3 sdram_a4 sdram_a5 vdda sdram_a6 sdram_a7
               sdram_a8 vssa sdram_a9 sdram_a10 sdram_a11 vssd sdram_a12 sdram_ba0 sdram_ba1 vddio}
set row(east)  {conn sdram_dq0 sdram_dq1 sdram_dq2 sdram_dq3 vddio sdram_dq4 sdram_dq5 sdram_dq6 sdram_dq7
               vccd sdram_dq8 sdram_dq9 sdram_dq10 sdram_dq11 vssio sdram_dq12 sdram_dq13 sdram_dq14 sdram_dq15 vssd}
set row(north) {conn spi_cs_n spi_sclk spi_mosi spi_miso vssd uart_tx uart_rx rst_n clk vddio mclk sdram_clk
               sdram_cke sdram_cs_n vccd sdram_ras_n sdram_cas_n sdram_we_n vssio sdram_dqm0 sdram_dqm1}
set row(west)  {conn vssio gpio15 gpio14 gpio13 gpio12 vccd gpio11 gpio10 gpio9 gpio8 vddio gpio7 gpio6 gpio5
               gpio4 vssd gpio3 gpio2 gpio1 gpio0}

array set supply_pad {
  vccd  sky130_ef_io__vccd_lvc_clamped_pad   vssd  sky130_ef_io__vssd_lvc_clamped_pad
  vddio sky130_ef_io__vddio_hvc_clamped_pad  vssio sky130_ef_io__vssio_hvc_clamped_pad
  vdda  sky130_ef_io__vdda_hvc_clamped_pad   vssa  sky130_ef_io__vssa_hvc_clamped_pad
  conn  sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um
}
set corner sky130_ef_io__corner_pad
# corner 200 x 204: its 204 edge abuts the north and south rows, its 200 edge the east and west rows
set cw 200
set ch 204

proc io_place {name master x y orient} {
  if {$master eq ""} {
    place_inst -name $name -location [list $x $y] -orientation $orient -status FIRM
  } else {
    place_inst -name $name -cell $master -location [list $x $y] -orientation $orient -status FIRM
  }
}

proc io_size {pad} {
  global supply_pad
  set block [ord::get_db_block]
  if {[info exists supply_pad($pad)]} {
    set m [[ord::get_db] findMaster $supply_pad($pad)]
  } else {
    set m [[$block findInst p_$pad.p] getMaster]
  }
  list [ord::dbu_to_microns [$m getWidth]] [ord::dbu_to_microns [$m getHeight]]
}

# bus slices for a gap of whole microns
proc io_fill {side x0 len} {
  foreach w {20 10 5 1} {
    while {$len >= $w} {
      lappend ::fill($side) [list $x0 $w]
      set x0 [expr {$x0 + $w}]
      set len [expr {$len - $w}]
    }
  }
}

set d [ord::dbu_to_microns [[[ord::get_db_block] getDieArea] xMax]]

io_place corner_sw $corner 0 0 R180
io_place corner_se $corner [expr {$d - $cw}] 0 MX
io_place corner_ne $corner [expr {$d - $cw}] [expr {$d - $ch}] R0
io_place corner_nw $corner 0 [expr {$d - $ch}] MY

foreach side {south east north west} {
  set pads $row($side)
  if {$side in {south north}} { set lo $cw } else { set lo $ch }
  set len [expr {$d - 2 * $lo}]
  set used 0
  foreach p $pads { set used [expr {$used + [lindex [io_size $p] 0]}] }
  set free [expr {int(floor($len - $used))}]
  set n [expr {[llength $pads] + 1}]
  set fill($side) {}
  # whole-micron gaps, the remainder spread from the start of the side
  set pos $lo
  set i 0
  foreach p $pads {
    set gap [expr {$free / $n + ($i < $free % $n)}]
    io_fill $side $pos $gap
    set pos [expr {$pos + $gap}]
    lassign [io_size $p] w h
    if {[info exists supply_pad($p)]} {
      set name ${p}_${side}
      set master $supply_pad($p)
    } else {
      set name p_$p.p
      set master ""
    }
    switch $side {
      south { io_place $name $master $pos 0 R180 }
      north { io_place $name $master $pos [expr {$d - $h}] R0 }
      west  { io_place $name $master 0 $pos R90 }
      east  { io_place $name $master [expr {$d - $h}] $pos R270 }
    }
    set pos [expr {$pos + $w}]
    incr i
  }
  io_fill $side $pos [expr {int(round($d - $lo - $pos))}]
}

set k 0
foreach side {south east north west} {
  foreach f $fill($side) {
    lassign $f pos w
    set master sky130_ef_io__com_bus_slice_${w}um
    set h 197.965
    set name io_fill_[incr k]
    switch $side {
      south { io_place $name $master $pos 0 R180 }
      north { io_place $name $master $pos [expr {$d - $h}] R0 }
      west  { io_place $name $master 0 $pos R90 }
      east  { io_place $name $master [expr {$d - $h}] $pos R270 }
    }
  }
}
