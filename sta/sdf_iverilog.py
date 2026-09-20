# Interconnect delays iverilog's SDF annotator can annotate: it stops on chip ports and escaped instance
# names (the pads and SRAMs), so those wires keep zero delay.
# Usage: python3 sta/sdf_iverilog.py <sdf> <out sdf>
import re, sys

src, dst = sys.argv[1:3]
out, dropped = [], 0
for line in open(src):
    m = re.match(r"\s*\(INTERCONNECT (\S+) (\S+) ", line)
    if m and ("/" not in m.group(1) or "/" not in m.group(2) or "\\" in line):
        dropped += 1
        continue
    out.append(line)
open(dst, "w").writelines(out)
print(f"{dst}: dropped {dropped} interconnect entries")
