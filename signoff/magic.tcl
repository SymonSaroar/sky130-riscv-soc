# Magic: DRC and LVS extraction. The SRAM is a hard macro, read as its LEF abstract.
set pdk  $::env(PDK_ROOT)/sky130A
set out  $::env(OUT)
set rep  $::env(REP)
set sram sky130_sram_2kbyte_1rw1r_32x512_8

drc off
gds readonly true
gds rescale false
gds read $pdk/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds
lef read $pdk/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
lef read $pdk/libs.ref/sky130_sram_macros/lef/$sram.lef
def read $out/soc_top.def
load soc_top
select top cell

drc euclidean on
drc style drc(full)
drc on
drc check
drc catchup
set f [open $rep/drc_magic.rpt w]
set n 0
foreach {why boxes} [drc listall why] {
  puts $f "[llength $boxes]\t$why"
  incr n [llength $boxes]
}
puts $f "total $n"
close $f

cd $out
extract no all
extract do local
extract unique
extract all
ext2spice lvs
ext2spice -o soc_top.lvs.spice soc_top
quit -noprompt
