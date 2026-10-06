# GLS copy of sky130_ef_io.v. The gpiov2 wrapper leaves off the supply pins the netlist does not have, so the
# pad model uses its own supplies, and takes per-instance transport delays on OUT, OE_N and IN, 0 unless a defparam
# sets them.
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
// transport delays: the pad passes pulses shorter than its propagation delay, and each change lands in the order it
// was made; t0 also carries inputs that settle at time 0 and never change
wire in_i;
reg out_d, oe_n_d, in_d, t0 = 1'b0;
integer n_out = 0, n_oe = 0, n_in = 0, a_out = 0, a_oe = 0, a_in = 0;
initial #0.001 t0 = 1'b1;
task automatic put_out(input v, input integer k);
  begin #(v === 1'b1 ? T_OUT_R : T_OUT_F); if (k > a_out) begin out_d = v; a_out = k; end end
endtask
task automatic put_oe(input v, input integer k);
  begin #(v === 1'b1 ? T_OE_R : T_OE_F); if (k > a_oe) begin oe_n_d = v; a_oe = k; end end
endtask
task automatic put_in(input v, input integer k);
  begin #(v === 1'b1 ? T_IN_R : T_IN_F); if (k > a_in) begin in_d = v; a_in = k; end end
endtask
always @(OUT or t0) begin n_out = n_out + 1; fork put_out(OUT, n_out); join_none end
always @(OE_N or t0) begin n_oe = n_oe + 1; fork put_oe(OE_N, n_oe); join_none end
always @(in_i or t0) begin n_in = n_in + 1; fork put_in(in_i, n_in); join_none end
assign IN = in_d;""")
m = m.replace(".IN(IN)", ".IN(in_i)").replace(".OE_N(OE_N)", ".OE_N(oe_n_d)").replace(".OUT(OUT)", ".OUT(out_d)")
assert all(p in m for p in ("T_OUT_R = 0", ".IN(in_i)", ".OE_N(oe_n_d)", ".OUT(out_d)"))
open(dst, "w").write(s[:i] + m + s[j:])
