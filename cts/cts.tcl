source config.tcl
load place

# the trees start at the clock pads' core-side outputs
clock_tree_synthesis -clk_nets {c_clk c_mclk} -root_buf sky130_fd_sc_hd__clkbuf_16 \
  -buf_list {sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_2} \
  -sink_clustering_enable
set_propagated_clock [all_clocks]
estimate_parasitics -placement
repair_clock_nets
estimate_parasitics -placement
repair_timing -setup
# hold margin at tt covers the fast corner
repair_timing -hold -hold_margin 0.2
detailed_placement
check_placement -verbose

report_clock_skew > $rep/cts.skew.rpt
report_stage cts
write_db $out/cts.odb
