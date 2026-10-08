# Shared settings for the OpenROAD stages.
set pdk      $::env(PDK_ROOT)/sky130A
set sc       $pdk/libs.ref/sky130_fd_sc_hd
set sm       $pdk/libs.ref/sky130_sram_macros
set sram     sky130_sram_2kbyte_1rw1r_32x512_8
set io       $pdk/libs.ref/sky130_fd_io
set tech_lef $sc/techlef/sky130_fd_sc_hd__nom.tlef
set out      $::env(OUT)
set rep      $::env(REP)

# floorplan: 3.2 mm die, the pad ring 20 um in from the edge, the core inside the pad ring and the power ring
set die      3200
set io_off   20
set core_off 285
set macro_channel 40

# estimated wire capacitance relative to the tech LEF, calibrated to OpenRCX; the max and min RC extractions
# have 1.096 and 0.90 times the nominal wire capacitance
set place_cap_scale 2.40
set grt_cap_scale   1.91
array set rc_scale {tt 1.0 ss 1.096 ff 0.90}
array set pvt {tt tt_025C_1v80 ss ss_100C_1v60 ff ff_n40C_1v95}
source constraints/corner.tcl

# placement
set place_density 0.5
set gpl_pad 4
set dpl_pad 2

proc read_libs {{corner tt}} {
  global sc sm sram io tech_lef pvt
  read_lef $tech_lef
  read_lef $sc/lef/sky130_fd_sc_hd.lef
  read_lef $sc/lef/sky130_ef_sc_hd.lef
  read_lef $sm/lef/$sram.lef
  read_lef $io/lef/sky130_ef_io.lef
  read_liberty $sc/lib/sky130_fd_sc_hd__$pvt($corner).lib
  read_liberty [expr {$corner eq "tt" ? "$sm/lib/${sram}_TT_1p8V_25C.lib" : "$::env(OUT)/sram_$corner.lib"}]
  read_liberty $::env(OUT)/gpiov2_$corner.lib
}

proc load {stage {corner tt}} {
  global out pdk
  read_libs $corner
  # wire RC from the tech LEF, taken before read_db: set_layer_rc stores its values in the database's layers
  set tech [[ord::get_db] getTech]
  foreach name {met1 met2 met3 met4 met5} {
    set l [$tech findLayer $name]
    set w [ord::dbu_to_microns [$l getWidth]]
    set r($name) [expr {[$l getResistance] / $w / 1000.0}]
    set c($name) [expr {[$l getCapacitance] * $w + 2 * [$l getEdgeCapacitance]}]
  }
  read_db $out/$stage.odb
  read_corner_sdc $corner $out
  set_placement_padding -global -left $::dpl_pad -right $::dpl_pad
  foreach name {met1 met2 met3 met4 met5} {
    set_layer_rc -layer $name -resistance $r($name) -capacitance [expr {$c($name) * $::grt_cap_scale * $::rc_scale($corner)}]
  }
  set_wire_rc -signal -resistance $r(met2) -capacitance [expr {$c(met2) * $::place_cap_scale * $::rc_scale($corner)}]
  set_wire_rc -clock -layer met5
  set f [open $pdk/libs.tech/openlane/sky130_fd_sc_hd/no_synth.cells]
  set_dont_use [concat [split [string trim [read $f]]] *lpflow* *probe*]
  close $f
}

proc report_stage {stage} {
  global rep
  if {$stage ne "grt"} { estimate_parasitics -placement }
  report_checks -path_delay max -fields {slew cap fanout} -format full_clock_expanded > $rep/$stage.setup.rpt
  report_checks -path_delay min > $rep/$stage.hold.rpt
  set f [open $rep/$stage.summary w]
  foreach {k v} [list wns [sta::worst_slack_cmd max] tns [sta::total_negative_slack_cmd max] \
                     whs [sta::worst_slack_cmd min]] {
    puts $f [format "%s %.3f" $k [expr {$v * 1e9}]]
  }
  close $f
  report_design_area
}
