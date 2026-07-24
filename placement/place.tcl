source config.tcl
load floorplan

global_placement -density $place_density -pad_left $gpl_pad -pad_right $gpl_pad
# A buffer next to every SRAM data, address and control input. The SRAM liberty limits
# these pins to 40 ps; the short buffer-to-pin nets stay out of repair.
set sram [[ord::get_db_block] findInst u_sram.mem]
foreach it [$sram getITerms] {
  set name [[$it getMTerm] getName]
  if {[$it getIoType] ne "INPUT" || [string match clk* $name] || [$it getNet] eq "NULL"} { continue }
  lassign [$it getAvgXY] ok x y
  set tag [string map {[ _ ] {}} $name]
  insert_buffer -buffer_cell sky130_fd_sc_hd__buf_4 -load_pins u_sram.mem/$name \
    -buffer_name sram_buf_$tag -net_name sram_$tag \
    -location [list [ord::dbu_to_microns $x] [ord::dbu_to_microns $y]]
  set_dont_touch [get_nets -of_objects [get_pins u_sram.mem/$name]]
}

estimate_parasitics -placement
repair_design
detailed_placement
check_placement -verbose

report_stage place
write_db $out/place.odb
