add_global_connection -net VPWR -pin_pattern {^(VPWR|VPB|vccd1)$} -power
add_global_connection -net VGND -pin_pattern {^(VGND|VNB|vssd1)$} -ground
global_connect
set_voltage_domain -power VPWR -ground VGND

define_pdn_grid -name core
add_pdn_stripe -grid core -layer met1 -width 0.48 -followpins
add_pdn_stripe -grid core -layer met4 -width 1.6 -pitch 153.6 -offset 16.32
add_pdn_stripe -grid core -layer met5 -width 1.6 -pitch 153.18 -offset 16.65
add_pdn_connect -grid core -layers {met1 met4}
add_pdn_connect -grid core -layers {met4 met5}

define_pdn_grid -macro -name sram -cells sky130_sram_2kbyte_1rw1r_32x512_8 -halo 5
add_pdn_connect -grid sram -layers {met4 met5}

pdngen
