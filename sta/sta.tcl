# Signoff STA in OpenSTA on the routed netlist with OpenRCX parasitics, one corner per run:
# tt (tt_025C_1v80, nominal RC), ss (ss_100C_1v60, max RC), ff (ff_n40C_1v95, min RC).
set pdk $::env(PDK_ROOT)/sky130A
set out $::env(OUT)
set rep $::env(REP)
set corner $::env(CORNER)
array set cells {tt tt_025C_1v80 ss ss_100C_1v60 ff ff_n40C_1v95}
array set rc    {tt nom ss max ff min}

read_liberty $pdk/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__$cells($corner).lib
if {$corner eq "tt"} {
  read_liberty $pdk/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
} else {
  read_liberty $out/sram_$corner.lib
}
read_liberty $out/gpiov2_$corner.lib
read_verilog $out/chip_top.final.v
link_design chip_top
read_sdc constraints/soc.sdc
set_propagated_clock [all_clocks]
read_spef $out/chip_top.$rc($corner).spef

set tag [expr {$corner eq "tt" ? "sta" : "sta_$corner"}]
report_checks -path_delay max -group_path_count 10 -fields {slew cap fanout} > $rep/$tag.setup.rpt
report_checks -path_delay min -group_path_count 10 > $rep/$tag.hold.rpt
report_check_types -max_slew -max_capacitance -max_fanout -violators > $rep/$tag.drv.rpt
if {$corner eq "tt"} {
  # pad cell power listed after the design total
  report_power > $rep/power.rpt
  report_power -instances [get_cells -filter "ref_name == sky130_ef_io__gpiov2_pad_wrapped" *] >> $rep/power.rpt
  report_checks -path_delay max -from [get_clocks clk] -to [get_clocks mclk] -group_path_count 5 > $rep/cdc.rpt
  report_checks -path_delay max -from [get_clocks mclk] -to [get_clocks clk] -group_path_count 5 >> $rep/cdc.rpt
  report_checks -path_delay max -from [get_clocks clk] -to [get_clocks pclk] -group_path_count 5 >> $rep/cdc.rpt
  report_checks -path_delay max -from [get_clocks pclk] -to [get_clocks clk] -group_path_count 5 >> $rep/cdc.rpt
}

set f [open $rep/$tag.summary w]
foreach {k v} [list wns [sta::worst_slack_cmd max] tns [sta::total_negative_slack_cmd max] \
                   whs [sta::worst_slack_cmd min] ths [sta::total_negative_slack_cmd min]] {
  puts $f [format "%s %.3f" $k [expr {$v * 1e9}]]
}
puts $f "viol_endpoints [sta::endpoint_violation_count max]"
puts $f "hold_viol_endpoints [sta::endpoint_violation_count min]"
# per clock domain; the SPI pins count toward clk and the SDRAM pins toward mclk
foreach {name groups} {clk {clk spi_clk} mclk {mclk sdram_clk} pclk pclk} {
  set ws ""
  foreach g $groups {
    set p [lindex [find_timing_paths -path_group $g -path_delay max -group_path_count 1] 0]
    if {$p ne "" && ($ws eq "" || [get_property $p slack] < $ws)} { set ws [get_property $p slack] }
  }
  if {$ws eq ""} continue
  set period [get_property [get_clocks $name] period]
  puts $f [format "wns_%s %.3f" $name $ws]
  puts $f [format "fmax%s_mhz %.1f" [expr {$name eq "clk" ? "" : "_$name"}] [expr {1e3 / ($period - $ws)}]]
}
close $f
