# SDF for iverilog: its annotator stops on chip ports and escaped instance names (the pads and SRAMs), so
# their interconnects and cell entries are dropped, and the empty typical values take the min-max value.
# Usage: python3 sta/sdf_iverilog.py <sdf> <out sdf>
import re, sys

src, dst = sys.argv[1:3]
s = open(src).read()
cells = re.split(r"(?=\n \(CELL\n)", s)
out, ic, dropped = [cells[0]], 0, 0
for c in cells[1:]:
    inst = re.search(r"\(INSTANCE ?([^)]*)\)", c).group(1)
    if "\\" in inst:
        dropped += 1
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
print(f"{dst}: dropped {dropped} cell entries and {ic} interconnect entries")
