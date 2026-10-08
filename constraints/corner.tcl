# SDC for a corner: soc.sdc, or at the slow corner clk at 50 MHz, mclk at 62.5 MHz and crossings bounded by 16 ns.
proc read_corner_sdc {corner out} {
  if {$corner ne "ss"} {
    read_sdc constraints/soc.sdc
    return
  }
  set f [open constraints/soc.sdc]
  set sdc [string map {"-name clk  -period 10" "-name clk  -period 20" "-name mclk -period 10" "-name mclk -period 16"
                       "set_max_delay 10" "set_max_delay 16"} [read $f]]
  close $f
  set f [open $out/soc_ss.sdc w]
  puts -nonewline $f $sdc
  close $f
  read_sdc $out/soc_ss.sdc
}
