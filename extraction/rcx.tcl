source config.tcl
load route
# nominal, minimum and maximum interconnect corners
foreach c {nom min max} {
  define_process_corner -ext_model_index 0 X
  extract_parasitics -ext_model_file $pdk/libs.tech/openlane/rules.openrcx.sky130A.$c.calibre
  write_spef $out/chip_top.$c.spef
}
