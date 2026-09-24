# Pad ring after the SkyWater I/O user guide: gpio pads abut with every other one mirrored, supply pads go in
# pairs, and the vssd/vccd pair keeps bus slices of at least 12 um on its outer sides, where its overlays reach.
# Signal pads are netlist instances p_<name>.p; conn is a slice that ties VCCHIB to VCCD and VSWITCH to VDDIO.
# Rows are in the cells' own left-to-right order: north and west run with the coordinate, south and east against it.
set row(south) {conn gpio3 gpio2 gpio1 gpio0 vdda vssa mclk sdram_clk sdram_cke sdram_cs_n sdram_ras_n sdram_cas_n
                sdram_we_n sdram_dqm0 sdram_dqm1 vddio vssio sdram_ba0 sdram_ba1 sdram_a0 sdram_a1 sdram_a2 sdram_a3
                sdram_a4 sdram_a5 vssd vccd sdram_a6 sdram_a7 sdram_a8 sdram_a9 sdram_a10 sdram_a11 sdram_a12}
set row(east)  {conn pipe_tx_data0 pipe_tx_data1 pipe_tx_data2 pipe_tx_data3 pipe_tx_data4 pipe_tx_data5 pipe_tx_data6
                pipe_tx_data7 vddio vssio pipe_tx_clk pipe_tx_data8 pipe_tx_data9 pipe_tx_data10 pipe_tx_data11
                pipe_tx_data12 pipe_tx_data13 pipe_tx_data14 pipe_tx_data15 pipe_tx_datak0 pipe_tx_datak1 vssd vccd
                pipe_tx_elecidle pipe_tx_compliance pipe_tx_det_loopback pipe_rx_polarity pipe_powerdown0
                pipe_powerdown1 vddio vssio pipe_reset_n gpio15 gpio14}
set row(north) {conn rst_n clk uart_rx uart_tx pipe_rx_elecidle pipe_phy_status pipe_rx_valid pipe_rx_status2
                pipe_rx_status1 pipe_rx_status0 pipe_rx_datak1 pipe_rx_datak0 vddio vssio pipe_rx_data15
                pipe_rx_data14 pipe_rx_data13 pipe_rx_data12 pipe_rx_data11 pipe_rx_data10 pipe_rx_data9 pipe_rx_data8
                pipe_rx_clk vssd vccd pipe_rx_data7 pipe_rx_data6 pipe_rx_data5 pipe_rx_data4 pipe_rx_data3
                pipe_rx_data2 pipe_rx_data1 pipe_rx_data0}
set row(west)  {conn sdram_dq0 sdram_dq1 sdram_dq2 sdram_dq3 sdram_dq4 sdram_dq5 sdram_dq6 sdram_dq7 vddio vssio
                sdram_dq8 sdram_dq9 sdram_dq10 sdram_dq11 sdram_dq12 sdram_dq13 sdram_dq14 sdram_dq15 vssd vccd
                spi_cs_n spi_sclk spi_mosi spi_miso gpio4 gpio5 gpio6 gpio7 gpio8 gpio9 gpio10 gpio11 gpio12 gpio13}

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
      if {[incr nsup($name)] > 1} { append name _$nsup($name) }
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
