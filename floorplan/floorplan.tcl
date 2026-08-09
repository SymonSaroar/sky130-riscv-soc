source config.tcl
read_libs
read_verilog $out/soc_top.v
link_design soc_top
read_sdc constraints/soc.sdc

initialize_floorplan -utilization $core_util -aspect_ratio $core_aspect \
  -core_space $core_space -site unithd

set f [open $pdk/libs.tech/openlane/sky130_fd_sc_hd/tracks.info]
foreach line [split [string trim [read $f]] \n] {
  lassign $line layer dir offset pitch
  set t($layer,$dir) [list $offset $pitch]
}
close $f
foreach layer {li1 met1 met2 met3 met4 met5} {
  lassign $t($layer,X) xo xp
  lassign $t($layer,Y) yo yp
  make_tracks $layer -x_offset $xo -x_pitch $xp -y_offset $yo -y_pitch $yp
}

# Program SRAM in the lower-left corner, cache SRAM in the upper-left corner (mirrored),
# with routing channels on their outer sides and both fetch ports facing the core.
# I/O pins stay off the edges the macros block.
set c [[ord::get_db_block] getCoreArea]
set x0 [expr {[ord::dbu_to_microns [$c xMin]] + $macro_channel}]
set h  [ord::dbu_to_microns [[[ord::get_db] findMaster sky130_sram_2kbyte_1rw1r_32x512_8] getHeight]]
place_macro -macro_name u_sram.mem -orientation R0 \
  -location [list $x0 [expr {[ord::dbu_to_microns [$c yMin]] + $macro_channel}]]
place_macro -macro_name u_icache.mem -orientation MX \
  -location [list $x0 [expr {[ord::dbu_to_microns [$c yMax]] - $macro_channel - $h}]]
set w [ord::dbu_to_microns [[[ord::get_db] findMaster sky130_sram_2kbyte_1rw1r_32x512_8] getWidth]]
place_pins -hor_layers met3 -ver_layers met2 -exclude left:* -exclude bottom:* \
  -exclude top:0-[expr {int($x0 + $w + $macro_channel)}]

tapcell -distance 13 -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1 \
  -endcap_master sky130_fd_sc_hd__decap_3 -halo_width_x 10 -halo_width_y 10
source floorplan/pdn.tcl

report_design_area
write_db $out/floorplan.odb
