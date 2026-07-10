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

place_pins -hor_layers met3 -ver_layers met2
set_macro_base_halo 10 10
rtl_macro_placer

tapcell -distance 13 -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1 \
  -endcap_master sky130_fd_sc_hd__decap_3
source floorplan/pdn.tcl

report_design_area
write_db $out/floorplan.odb
