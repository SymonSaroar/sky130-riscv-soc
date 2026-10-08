source config.tcl
read_libs
read_verilog $out/chip_top.v
link_design chip_top
read_sdc constraints/soc.sdc

set c1 [expr {$die - $core_off}]
initialize_floorplan -die_area [list 0 0 $die $die] -core_area [list $core_off $core_off $c1 $c1] -site unithd

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

source floorplan/padring.tcl
# chip pins on the bond pads
place_io_terminals [get_pins {*/PAD */P_PAD}]

# Program SRAM in the lower-left corner, cache SRAM in the upper-left corner (mirrored),
# with routing channels on their outer sides and both fetch ports facing the core.
set c [[ord::get_db_block] getCoreArea]
set x0 [expr {[ord::dbu_to_microns [$c xMin]] + $macro_channel}]
set h  [ord::dbu_to_microns [[[ord::get_db] findMaster sky130_sram_2kbyte_1rw1r_32x512_8] getHeight]]
place_macro -macro_name u_core.u_sram.mem -orientation R0 \
  -location [list $x0 [expr {[ord::dbu_to_microns [$c yMin]] + $macro_channel}]]
place_macro -macro_name u_core.u_icache.mem -orientation MX \
  -location [list $x0 [expr {[ord::dbu_to_microns [$c yMax]] - $macro_channel - $h}]]

# PCIe PHY against the east edge of the core, centred on its pads: no rows between its pad-side pins and the core
# ring, so its analog supply straps pass under the ring clear of the rails' vias
set ys {}
foreach inst [[ord::get_db_block] getInsts] {
  if {[string match p_pcie_* [$inst getName]]} {
    set bb [$inst getBBox]
    lappend ys [expr {([$bb yMin] + [$bb yMax]) / 2}]
  }
}
set m [[ord::get_db] findMaster pcie_phy]
set yc [ord::dbu_to_microns [expr {([tcl::mathfunc::min {*}$ys] + [tcl::mathfunc::max {*}$ys]) / 2}]]
place_macro -macro_name u_phy -orientation R0 \
  -location [list [expr {[ord::dbu_to_microns [$c xMax]] - [ord::dbu_to_microns [$m getWidth]]}] \
                  [expr {$yc - [ord::dbu_to_microns [$m getHeight]] / 2}]]

tapcell -distance 13 -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1 \
  -endcap_master sky130_fd_sc_hd__decap_3 -halo_width_x 10 -halo_width_y 10
source floorplan/pdn.tcl

report_design_area
write_db $out/floorplan.odb
