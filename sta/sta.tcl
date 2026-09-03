# Signoff STA in OpenSTA on the routed netlist with OpenRCX parasitics.
set pdk $::env(PDK_ROOT)/sky130A
set out $::env(OUT)
set rep $::env(REP)

read_liberty $pdk/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $pdk/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
read_liberty $out/gpiov2_sta.lib
read_verilog $out/chip_top.final.v
link_design chip_top
read_sdc constraints/soc.sdc
set_propagated_clock [all_clocks]
read_spef $out/chip_top.spef

report_checks -path_delay max -group_path_count 10 -fields {slew cap fanout} > $rep/sta.setup.rpt
report_checks -path_delay min -group_path_count 10 > $rep/sta.hold.rpt
report_check_types -max_slew -max_capacitance -max_fanout -violators > $rep/sta.drv.rpt
# pad cell power listed after the design total
report_power > $rep/power.rpt
report_power -instances [get_cells -filter "ref_name == sky130_ef_io__gpiov2_pad_wrapped" *] >> $rep/power.rpt
if {[llength [all_clocks]] > 1} {
  report_checks -path_delay max -from [get_clocks clk] -to [get_clocks mclk] -group_path_count 5 > $rep/cdc.rpt
  report_checks -path_delay max -from [get_clocks mclk] -to [get_clocks clk] -group_path_count 5 >> $rep/cdc.rpt
}

set f [open $rep/sta.summary w]
foreach {k v} [list wns [sta::worst_slack_cmd max] tns [sta::total_negative_slack_cmd max] \
                   whs [sta::worst_slack_cmd min] ths [sta::total_negative_slack_cmd min]] {
  puts $f [format "%s %.3f" $k [expr {$v * 1e9}]]
}
puts $f "viol_endpoints [sta::endpoint_violation_count max]"
puts $f "hold_viol_endpoints [sta::endpoint_violation_count min]"
# per clock domain; the SDRAM I/O paths count toward mclk
foreach {name groups} {clk clk mclk {mclk sdram_clk}} {
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
