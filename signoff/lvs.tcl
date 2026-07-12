# Netgen: layout netlist vs. powered Verilog netlist
set pdk $::env(PDK_ROOT)/sky130A
set out $::env(OUT)
set rep $::env(REP)

set lay [readnet spice $out/soc_top.lvs.spice]
set sch [readnet spice $pdk/libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice]
readnet verilog $out/soc_top.pwr.v $sch
lvs "$lay soc_top" "$sch soc_top" $pdk/libs.tech/netgen/sky130A_setup.tcl $rep/lvs.rpt -blackbox
quit
