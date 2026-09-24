# gpiov2 pad liberty for timing: only the arcs the chip's pad settings can enable, and no IN function.
# Usage: python3 sta/pad_lib.py <pdk lib> <out lib>
import itertools, re, sys

# pins tied by chip_top.v; DM is 110 on outputs and bidirectional pins, 001 on inputs; IB_MODE_SEL is 1 on the
# 1.8 V inputs and 0 on the others, so the arcs of both input buffers stay
TIES = dict(SLOW=0, VTRIP_SEL=0, INP_DIS=0, HLD_OVR=0, ANALOG_EN=0, ANALOG_SEL=0, ANALOG_POL=0,
            ENABLE_H=1, HLD_H_N=1, ENABLE_VDDA_H=1, ENABLE_INP_H=0, ENABLE_VSWITCH_H=0, ENABLE_VDDIO=1)
MODES = [(1, 1, 0), (0, 0, 1)]


def possible(when):
    expr = when.replace("DM[2]", "DM2").replace("DM[1]", "DM1").replace("DM[0]", "DM0")
    expr = expr.replace("&", " and ").replace("|", " or ").replace("!", " not ").replace("*", " and ")
    names = set(re.findall(r"[A-Za-z_]\w*", expr)) - {"and", "or", "not"}
    free = sorted(n for n in names if n not in TIES and not n.startswith("DM"))
    for dm in MODES:
        for vals in itertools.product([0, 1], repeat=len(free)):
            env = dict(TIES, DM2=dm[0], DM1=dm[1], DM0=dm[2], **dict(zip(free, vals)))
            if eval(expr, {}, env):
                return True
    return False


def group_end(s, start):
    depth, j = 0, start
    while True:
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1


src, dst = sys.argv[1:3]
s = open(src).read()
s = s.replace('function : "(PAD&!INP_DIS)";', "")
out, i, dropped = [], 0, 0
for m in re.finditer(r"\n\s*timing \(\) \{", s):
    if m.start() < i:
        continue
    end = group_end(s, m.end() - 1)
    w = re.search(r'when : "([^"]*)"', s[m.end():end])
    if w and not possible(w.group(1)):
        out.append(s[i:m.start()])
        i = end
        dropped += 1
out.append(s[i:])
open(dst, "w").write("".join(out))
print(f"{dst}: dropped {dropped} timing groups")
