# SDF for iverilog: its annotator stops on chip ports and escaped instance names (the pads and SRAMs), so
# their interconnects and cell entries are dropped, and the empty typical values take the min-max value.
# The pad delays go to a module of defparams for the GLS copy of the gpiov2 wrapper (tb/pad_gls.py), each pad
# taking the input arc of the IB_MODE_SEL its tie cell sets in the netlist.
# Usage: python3 sta/sdf_iverilog.py <sdf> <netlist> <out sdf> <out pads.v>
import re, sys

src, netlist, dst, pads = sys.argv[1:5]
s = open(src).read()
v = open(netlist).read()
high = set(re.findall(r"\.HI\((\S+?)\)", v))
ib = {name: net in high for name, body in re.findall(r"gpiov2_pad_wrapped \\(\S+)\s+\(([^;]*)\);", v)
      for net in re.findall(r"\.IB_MODE_SEL\((\S+?)\)", body)}
cells = re.split(r"(?=\n \(CELL\n)", s)
out, ic, dropped, dp = [cells[0]], 0, 0, []
for c in cells[1:]:
    inst = re.search(r"\(INSTANCE ?([^)]*)\)", c).group(1)
    if "\\" in inst:
        dropped += 1
        if "gpiov2_pad_wrapped" in c:
            name = inst.replace("\\", "")
            for cond, a, b, r, f in re.findall(
                    r"(?:\(COND\s+([^(]*?)\s*)?\(IOPATH (\w+) (\w+) \((-?[\d.]+):[^)]*\) \((-?[\d.]+):", c):
                k = {("OUT", "PAD"): "OUT", ("OE_N", "PAD"): "OE", ("PAD", "IN"): "IN"}.get((a, b))
                mode = re.search(r"IB_MODE_SEL==1'b([01])", cond)
                if k and not (mode and (mode.group(1) == "1") != ib[name]):
                    dp.append(f"  defparam tb_soc.dut.\\{name} .T_{k}_R = {r}, tb_soc.dut.\\{name} .T_{k}_F = {f};")
        continue
    lines = []
    for line in c.split("\n"):
        m = re.match(r"\s*\(INTERCONNECT (\S+) (\S+) ", line)
        if m and ("/" not in m.group(1) or "/" not in m.group(2) or "\\" in line):
            ic += 1
            continue
        lines.append(line)
    out.append("\n".join(lines))
s = "".join(out)
if not s.rstrip().endswith(")"):
    s += ")\n"
s = re.sub(r"(-?[\d.]+)::(-?[\d.]+)", r"\1:\1:\2", s)
open(dst, "w").write(s)
open(pads, "w").write(f"// pad delays from {src}\nmodule sdf_pads;\n" + "\n".join(dp) + "\nendmodule\n")
print(f"{dst}: dropped {dropped} cell entries and {ic} interconnect entries; {pads}: {len(dp)} pad delays")
