# SRAM liberty for a corner the macro has no characterization for: the TT tables scaled by the ratio
# the standard-cell flops show at that corner. Delays and transitions scale at both corners, setup
# constraints at the slow corner only; hold constraints keep their TT values.
# Usage: python3 sta/sram_lib.py <TT lib> ss|ff <out lib>
import re, sys

SCALE = {"ss": 2.1, "ff": 0.64}   # dfxtp_2 clock to Q, ss_100C_1v60 and ff_n40C_1v95 over tt_025C_1v80
DELAY = ("cell_rise", "cell_fall", "rise_transition", "fall_transition")

src, corner, dst = sys.argv[1:4]
k = SCALE[corner]
s = open(src).read()


def scale_values(group):
    return re.sub(r"values\((.*?)\);", lambda m: "values(" + re.sub(
        r"-?\d+\.?\d*(?:e-?\d+)?", lambda n: f"{float(n.group()) * k:.4f}", m.group(1)) + ");", group, flags=re.S)


def scale_timing(m):
    t = m.group(0)
    kind = re.search(r"timing_type\s*:\s*\"?(\w+)", t)
    kind = kind.group(1) if kind else ""
    names = DELAY + (("rise_constraint", "fall_constraint") if kind.startswith("setup") and corner == "ss" else ())
    for name in names:
        t = re.sub(name + r"\s*\([^)]*\)\s*\{.*?\}", lambda g: scale_values(g.group(0)), t, flags=re.S)
    return t


# timing groups hold no nested braces apart from their tables
s = re.sub(r"timing\(\)\s*\{(?:[^{}]|\{[^{}]*\})*\}", scale_timing, s)
open(dst, "w").write(s)
