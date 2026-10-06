# GLS copy of the sky130 HD primitives for simulation under constant supplies: every flop and latch starts at 0 or 1,
# the tables take their functional rows and the unconditional rows after them, supply changes hold the state, and
# rows match whatever the supply inputs read while they settle at time 0.
# Usage: python3 tb/primitives_gls.py <primitives.v> <0|1> <out>
import re, sys

src, init, dst = sys.argv[1:4]
parts = []
for part in re.split(r"(?=\nprimitive )", open(src).read()):
    lines = []
    for line in part.split("\n"):
        m = re.match(r"(\s*)// \['(IfDef\(functional\)|EndIfDef\(functional\))', ''\]\s*(.*)", line)
        if m:
            line = m.group(1) + m.group(3)
        if re.search(r"any change on (vpwr|vgnd)", line) and not line.lstrip().startswith("//"):
            line = re.sub(r":\s*[xX]\s*;", ": - ;", line)
        lines.append(line)
        if re.match(r"\s*reg Q;", line):
            lines.append(re.match(r"(\s*)", line).group(1) + f"initial Q = 1'b{init};")
    name = re.match(r"\nprimitive (\S+)", part)
    if name and "_pp$PG" in name.group(1) and "pwrgood" not in name.group(1):
        text = "\n".join(lines)
        a, b = text.index("table"), text.index("endtable")
        cols = re.search(r"//\s*(.*?):\s*Qt", text[a:b]).group(1).split()
        rows = []
        for line in text[a:b].split("\n"):
            body, _, note = line.partition("//")
            if ":" in body and not line.lstrip().startswith("table"):
                left, rest = body.split(":", 1)
                toks = left.split()
                toks = ["?" if c in ("VPWR", "VGND") and t in ("0", "1") else t for c, t in zip(cols, toks)] + toks[len(cols):]
                line = "    " + " ".join(toks) + " :" + rest + ("//" + note if note else "")
            rows.append(line)
        lines = (text[:a] + "\n".join(rows) + text[b:]).split("\n")
    parts.append("\n".join(lines))
open(dst, "w").write("".join(parts))
