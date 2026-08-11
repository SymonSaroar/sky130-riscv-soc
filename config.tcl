# Shared settings for the OpenROAD stages.
set pdk      $::env(PDK_ROOT)/sky130A
set sc       $pdk/libs.ref/sky130_fd_sc_hd
set sm       $pdk/libs.ref/sky130_sram_macros
set sram     sky130_sram_2kbyte_1rw1r_32x512_8
set tech_lef $sc/techlef/sky130_fd_sc_hd__nom.tlef
set out      $::env(OUT)
set rep      $::env(REP)

# floorplan
set core_util   52
set core_aspect 1
set core_space  10
set macro_channel 40

# estimated wire capacitance relative to the tech LEF, calibrated to OpenRCX
set place_cap_scale 2.40
set grt_cap_scale   1.91

# placement
set place_density 0.6
set gpl_pad 4
set dpl_pad 2

proc read_libs {} {
  global sc sm sram tech_lef
  read_lef $tech_lef
  read_lef $sc/lef/sky130_fd_sc_hd.lef
  read_lef $sm/lef/$sram.lef
  read_liberty $sc/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
  read_liberty $sm/lib/${sram}_TT_1p8V_25C.lib
}

proc load {stage} {
  global out pdk
  read_libs
  read_db $out/$stage.odb
  read_sdc constraints/soc.sdc
  set_placement_padding -global -left $::dpl_pad -right $::dpl_pad
  set tech [[ord::get_db] getTech]
  foreach name {met1 met2 met3 met4 met5} {
    set l [$tech findLayer $name]
    set w [ord::dbu_to_microns [$l getWidth]]
    set r [expr {[$l getResistance] / $w / 1000.0}]
    set c [expr {[$l getCapacitance] * $w + 2 * [$l getEdgeCapacitance]}]
    set_layer_rc -layer $name -resistance $r -capacitance [expr {$c * $::grt_cap_scale}]
    if {$name eq "met2"} {
      set_wire_rc -signal -resistance $r -capacitance [expr {$c * $::place_cap_scale}]
    }
  }
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
