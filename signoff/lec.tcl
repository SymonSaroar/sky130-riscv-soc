# Equivalence of the synthesized and the routed netlist. Flops, SRAMs and pads are cut points matched by
# instance name; ABC proves the combinational miter that is left.
yosys -import
set pdk $::env(PDK_ROOT)/sky130A
set out $::env(OUT)

read_liberty -lib $out/gpiov2_tt.lib
read_liberty -lib $pdk/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
read_liberty -ignore_miss_func $pdk/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
blackbox sky130_fd_sc_hd__df*
read_verilog $out/chip_top.v
yosys rename chip_top gold
read_verilog $out/chip_top.final.v
yosys rename chip_top gate
delete t:sky130_fd_sc_hd__tapvpwrvgnd_1 t:sky130_fd_sc_hd__fill_* t:sky130_fd_sc_hd__decap_* t:sky130_fd_sc_hd__diode_2
hierarchy -check
flatten gold gate
set cut {}
foreach m {gold gate} {
  foreach t {sky130_sram_* sky130_ef_io__* sky130_fd_sc_hd__df*} { lappend cut $m/t:$t }
}
expose -evert {*}$cut
setundef -undriven -expose gold gate
miter -equiv -flatten gold gate miter
hierarchy -top miter
techmap
opt_clean
aigmap
write_aiger $out/lec.aig
