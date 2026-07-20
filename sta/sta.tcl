# Signoff STA in OpenSTA on the routed netlist with OpenRCX parasitics.
set pdk $::env(PDK_ROOT)/sky130A
set out $::env(OUT)
set rep $::env(REP)

read_liberty $pdk/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $pdk/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
read_verilog $out/soc_top.final.v
link_design soc_top
read_sdc constraints/soc.sdc
set_propagated_clock [all_clocks]
read_spef $out/soc_top.spef

report_checks -path_delay max -group_path_count 10 -fields {slew cap fanout} > $rep/sta.setup.rpt
report_checks -path_delay min -group_path_count 10 > $rep/sta.hold.rpt
report_check_types -max_slew -max_capacitance -max_fanout -violators > $rep/sta.drv.rpt
report_power > $rep/power.rpt

set f [open $rep/sta.summary w]
foreach {k v} [list wns [sta::worst_slack_cmd max] tns [sta::total_negative_slack_cmd max] \
                   whs [sta::worst_slack_cmd min] ths [sta::total_negative_slack_cmd min]] {
  puts $f [format "%s %.3f" $k [expr {$v * 1e9}]]
}
puts $f "viol_endpoints [sta::endpoint_violation_count max]"
set period [get_property [get_clocks clk] period]
puts $f [format "fmax_mhz %.1f" [expr {1e3 / ($period - [sta::worst_slack_cmd max] * 1e9)}]]
close $f
