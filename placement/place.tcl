source config.tcl
load floorplan

global_placement -density $place_density
estimate_parasitics -placement
repair_design
detailed_placement
check_placement -verbose

report_stage place
write_db $out/place.odb
