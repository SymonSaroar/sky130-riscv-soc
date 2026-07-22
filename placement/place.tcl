source config.tcl
load floorplan

global_placement -density $place_density -pad_left $gpl_pad -pad_right $gpl_pad
estimate_parasitics -placement
# SRAM inputs carry a 40 ps max_transition from the macro's characterization range
set sram_in [get_nets -of_objects [get_pins u_sram.mem/* -filter "direction == input && name !~ clk*"]]
set_dont_touch $sram_in
repair_design
unset_dont_touch $sram_in
detailed_placement
check_placement -verbose

report_stage place
write_db $out/place.odb
