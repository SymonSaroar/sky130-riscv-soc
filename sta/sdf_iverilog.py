# SDF for iverilog: its annotator stops on chip ports and escaped instance names (the pads and SRAMs), so
# their interconnects and cell entries are dropped, and the empty typical values take the min-max value.
# The pad delays go to a module of defparams for the GLS copy of the gpiov2 wrapper (tb/pad_gls.py).
# Usage: python3 sta/sdf_iverilog.py <sdf> <out sdf> <out pads.v>
import re, sys

src, dst, pads = sys.argv[1:4]
s = open(src).read()
cells = re.split(r"(?=\n \(CELL\n)", s)
out, ic, dropped, dp = [cells[0]], 0, 0, []
for c in cells[1:]:
    inst = re.search(r"\(INSTANCE ?([^)]*)\)", c).group(1)
    if "\\" in inst:
        dropped += 1
        if "gpiov2_pad_wrapped" in c:
            for a, b, r, f in re.findall(r"\(IOPATH (\w+) (\w+) \((-?[\d.]+):[^)]*\) \((-?[\d.]+):", c):
                k = {("OUT", "PAD"): "OUT", ("OE_N", "PAD"): "OE", ("PAD", "IN"): "IN"}.get((a, b))
                if k:
                    name = inst.replace("\\", "")
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
