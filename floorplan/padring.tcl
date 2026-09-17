# Pad ring after the SkyWater I/O user guide: gpio pads abut with every other one mirrored, supply pads go in
# pairs, and the vssd/vccd pair keeps bus slices of at least 12 um on its outer sides, where its overlays reach.
# Signal pads are netlist instances p_<name>.p; conn is a slice that ties VCCHIB to VCCD and VSWITCH to VDDIO.
# Rows are in the cells' own left-to-right order: north and west run with the coordinate, south and east against it.
set row(south) {conn sdram_a0 sdram_a1 sdram_a2 sdram_a3 vddio vssio sdram_a4 sdram_a5 sdram_a6 sdram_a7 sdram_a8
               vssd vccd sdram_a9 sdram_a10 sdram_a11 sdram_a12 vdda vssa sdram_ba0 sdram_ba1}
set row(east)  {conn sdram_dq0 sdram_dq1 sdram_dq2 sdram_dq3 sdram_dq4 sdram_dq5 sdram_dq6 sdram_dq7 vddio vssio
               sdram_dq8 sdram_dq9 sdram_dq10 sdram_dq11 vssd vccd sdram_dq12 sdram_dq13 sdram_dq14 sdram_dq15}
set row(north) {conn spi_cs_n spi_sclk spi_mosi spi_miso uart_tx uart_rx rst_n clk vddio vssio mclk sdram_clk
               sdram_cke sdram_cs_n vssd vccd sdram_ras_n sdram_cas_n sdram_we_n sdram_dqm0 sdram_dqm1}
set row(west)  {conn gpio15 gpio14 gpio13 gpio12 gpio11 gpio10 gpio9 gpio8 vddio vssio gpio7 gpio6 gpio5 gpio4
               vssd vccd gpio3 gpio2 gpio1 gpio0}

array set supply_pad {
  vccd  sky130_ef_io__vccd_lvc_clamped_pad   vssd  sky130_ef_io__vssd_lvc_clamped_pad
  vddio sky130_ef_io__vddio_hvc_clamped_pad  vssio sky130_ef_io__vssio_hvc_clamped_pad
  vdda  sky130_ef_io__vdda_hvc_clamped_pad   vssa  sky130_ef_io__vssa_hvc_clamped_pad
  conn  sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um
}
array set mirrored {vssio 1 vssa 1 vssd 1}
array set base {south R180 north R0 west R90 east R270}
array set flip {south MX north MY west MYR90 east MXR90}
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

# the ring sits io_off in from the die edge
set o $io_off
set d [expr {[ord::dbu_to_microns [[[ord::get_db_block] getDieArea] xMax]] - $o}]

io_place corner_sw $corner $o $o R180
io_place corner_se $corner [expr {$d - $cw}] $o MX
io_place corner_ne $corner [expr {$d - $cw}] [expr {$d - $ch}] R0
io_place corner_nw $corner $o [expr {$d - $ch}] MY

foreach side {south east north west} {
  set pads $row($side)
  if {$side in {south north}} { set lo [expr {$o + $cw}] } else { set lo [expr {$o + $ch}] }
  set len [expr {$d - $lo - ($lo - $o)}]
  set used 0
  foreach p $pads { set used [expr {$used + [lindex [io_size $p] 0]}] }
  set free [expr {int(round($len - $used))}]
  if {$free < 24} { error "pad ring: the $side side needs [expr {24 - $free}] um more" }

  # in the cells' own order: the spare length split around the vssd/vccd pair, gpio pads alternately mirrored
  set seq {}
  set g 0
  foreach p $pads {
    if {$p eq "vssd"} { lappend seq [list gap [expr {$free / 2}]] }
    if {[info exists supply_pad($p)]} {
      lappend seq [list $p [info exists mirrored($p)]]
    } else {
      lappend seq [list $p [expr {[incr g] % 2 == 0}]]
    }
    if {$p eq "vccd"} { lappend seq [list gap [expr {$free - $free / 2}]] }
  }
  if {$side in {south east}} { set seq [lreverse $seq] }

  set fill($side) {}
  set pos $lo
  foreach e $seq {
    lassign $e p m
    if {$p eq "gap"} {
      io_fill $side $pos $m
      set pos [expr {$pos + $m}]
      continue
    }
    lassign [io_size $p] w h
    if {[info exists supply_pad($p)]} {
      set name ${p}_${side}
      set master $supply_pad($p)
    } else {
      set name p_$p.p
      set master ""
    }
    set orient [expr {$m ? $flip($side) : $base($side)}]
    switch $side {
      south { io_place $name $master $pos $o $orient }
      north { io_place $name $master $pos [expr {$d - $h}] $orient }
      west  { io_place $name $master $o $pos $orient }
      east  { io_place $name $master [expr {$d - $h}] $pos $orient }
    }
    set pos [expr {$pos + $w}]
  }
}

set k 0
foreach side {south east north west} {
  foreach f $fill($side) {
    lassign $f pos w
    set master sky130_ef_io__com_bus_slice_${w}um
    set h 197.965
    set name io_fill_[incr k]
    switch $side {
      south { io_place $name $master $pos $o $base($side) }
      north { io_place $name $master $pos [expr {$d - $h}] $base($side) }
      west  { io_place $name $master $o $pos $base($side) }
      east  { io_place $name $master [expr {$d - $h}] $pos $base($side) }
    }
  }
}
