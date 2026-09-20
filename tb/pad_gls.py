# GLS copy of sky130_ef_io.v. The gpiov2 wrapper leaves off the supply pins the netlist does not have, so the
# pad model uses its own supplies, and takes per-instance delays on OUT, OE_N and IN, 0 unless a defparam sets them.
# Usage: python3 tb/pad_gls.py <sky130_ef_io.v> <out>
import re, sys

src, dst = sys.argv[1:3]
s = open(src).read()
i = s.index("module sky130_ef_io__gpiov2_pad_wrapped")
j = s.index("endmodule", i)
m = re.sub(r"\n *\.(VSSA|VDDA|VSWITCH|VDDIO_Q|VCCHIB|VDDIO|VCCD|VSSIO|VSSD|VSSIO_Q)\(.*", "", s[i:j])
m = m.replace(".AMUXBUS_B(AMUXBUS_B),", ".AMUXBUS_B(AMUXBUS_B)")
m = m.replace("output TIE_HI_ESD, TIE_LO_ESD;", """output TIE_HI_ESD, TIE_LO_ESD;
parameter real T_OUT_R = 0, T_OUT_F = 0, T_OE_R = 0, T_OE_F = 0, T_IN_R = 0, T_IN_F = 0;
wire out_d, oe_n_d, in_i;
assign #(T_OUT_R, T_OUT_F) out_d = OUT;
assign #(T_OE_R, T_OE_F) oe_n_d = OE_N;
assign #(T_IN_R, T_IN_F) IN = in_i;""")
m = m.replace(".IN(IN)", ".IN(in_i)").replace(".OE_N(OE_N)", ".OE_N(oe_n_d)").replace(".OUT(OUT)", ".OUT(out_d)")
assert all(p in m for p in ("T_OUT_R = 0", ".IN(in_i)", ".OE_N(oe_n_d)", ".OUT(out_d)"))
open(dst, "w").write(s[:i] + m + s[j:])
