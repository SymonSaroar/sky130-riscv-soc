source config.tcl
load route
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file $pdk/libs.tech/openlane/rules.openrcx.sky130A.nom.calibre
write_spef $out/soc_top.spef
