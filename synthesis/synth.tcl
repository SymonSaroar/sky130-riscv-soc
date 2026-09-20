yosys -import
proc read_file {f} { set h [open $f]; set d [read $h]; close $h; return $d }
set pdk  $::env(PDK_ROOT)/sky130A
set lib  $pdk/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set sram $pdk/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
set io   $pdk/libs.ref/sky130_fd_io/verilog/sky130_ef_io.v
set out  $::env(OUT)
set rep  $::env(REP)

regexp {\-period\s+([0-9.]+)} [read_file constraints/soc.sdc] -> period
set dont_use {-dont_use *lpflow* -dont_use *probe*}
foreach c [split [string trim [read_file $pdk/libs.tech/openlane/sky130_fd_sc_hd/no_synth.cells]]] {
  lappend dont_use -dont_use $c
}

read_liberty -lib $lib
read_liberty -lib $sram
read_verilog -lib $io
read_verilog {*}[glob rtl/*.v]
# Booth multipliers, Kogge-Stone carry for adders and comparators
synth -top chip_top -flatten -booth -run :fine
techmap -map +/techmap.v -map +/choices/kogge-stone.v
synth -top chip_top -flatten -run fine:
dfflibmap -liberty $lib {*}$dont_use
abc -D [expr {$period * 1000}] -liberty $lib {*}$dont_use
setundef -zero
hilomap -singleton -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
splitnets
opt_clean -purge
tee -o $rep/synth_stat.txt stat -liberty $lib -liberty $sram
write_verilog -noattr -noexpr -nohex -nodec $out/chip_top.v
