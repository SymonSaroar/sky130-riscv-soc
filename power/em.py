# Electromigration on the core supply: PDNSim segment currents against the tech LEF average-current limits.
# Wires are judged by the metal width across the segment, vias by the cuts where the two metals overlap.
import csv, os, re
import pya

out, rep = os.environ["OUT"], os.environ["REP"]
tlef = open(os.environ["PDK_ROOT"] + "/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef").read()
block = {n: b for n, b in re.findall(r"^LAYER (\w+)\n(.*?)^END \1", tlef, re.S | re.M)}
limit = {n: float(re.search(r"DCCURRENTDENSITY AVERAGE ([\d.]+)", b)[1]) for n, b in block.items() if "DCCURRENT" in b}
minw = {n: float(re.search(r"^\s*WIDTH ([\d.]+)", b, re.M)[1]) for n, b in block.items() if n.startswith("met")}
metal = {"met1": (68, 20), "met2": (69, 20), "met3": (70, 20), "met4": (71, 20), "met5": (72, 20)}
via = {("met1", "met2"): ("via", (68, 44)), ("met2", "met3"): ("via2", (69, 44)),
       ("met3", "met4"): ("via3", (70, 44)), ("met4", "met5"): ("via4", (71, 44))}

ly = pya.Layout()
ly.read(out + "/chip_top.gds")
top = ly.top_cell()
um = lambda v: int(round(v / ly.dbu))


def shapes(layer, box):
    return pya.Region(top.begin_shapes_rec_touching(ly.find_layer(*layer), box)).merged()


def width(layer, x0, y0, x1, y1):
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    across = pya.Box(um(mx) - 1, um(my - 50), um(mx) + 1, um(my + 50)) if abs(x1 - x0) > abs(y1 - y0) else \
        pya.Box(um(mx - 50), um(my) - 1, um(mx + 50), um(my) + 1)
    hit = pya.Box(um(mx) - 1, um(my) - 1, um(mx) + 1, um(my) + 1)
    piece = (shapes(layer, across) & pya.Region(across)).interacting(pya.Region(hit))
    b = piece.bbox()
    return max(b.width(), b.height()) * ly.dbu


# PDNSim may put a via's two nodes apart, the lower one on the nearest node of its metal: look across both
def cuts(pair, x0, y0, x1, y1):
    name, cut = via[pair]
    p = pya.Region(pya.Box(um(min(x0, x1)) - 1, um(min(y0, y1)) - 1, um(max(x0, x1)) + 1, um(max(y0, y1)) + 1))
    lo, hi = (shapes(metal[m], p.bbox()).interacting(p) for m in pair)
    n = pya.Region(top.begin_shapes_rec_touching(ly.find_layer(*cut), (lo & hi).bbox())).inside(lo & hi).count()
    return n or pya.Region(top.begin_shapes_rec_touching(ly.find_layer(*cut), p.bbox().enlarged(um(2), um(2)))).count()


worst, over = {}, []
for net in ("VPWR", "VGND"):
    for r in csv.DictReader(open(f"{out}/em_{net}.csv")):
        a, b = r["Node0 Layer"], r["Node1 Layer"]
        x0, y0, x1, y1 = (float(r[f"Node{k} {c} location"]) for k in "01" for c in "XY")
        i = abs(float(r["Current"])) * 1e3
        if a == b:
            if a not in metal or i <= limit[a] * minw[a]:
                continue
            kind, cap = a, limit[a] * width(metal[a], x0, y0, x1, y1)
        else:
            pair = tuple(sorted((a, b)))
            if pair not in via or i <= limit[via[pair][0]]:
                continue
            kind, cap = via[pair][0], limit[via[pair][0]] * cuts(pair, x0, y0, x1, y1)
        if cap == 0:
            over.append(f"{net} {kind} {i:.3f} mA at ({x0:.2f}, {y0:.2f}), no metal found at the node")
            continue
        if i / cap > worst.get(kind, (0,))[0]:
            worst[kind] = (i / cap, i, cap, x0, y0)
        if i > cap:
            over.append(f"{net} {kind} {i:.3f} mA at ({x0:.2f}, {y0:.2f}), limit {cap:.3f} mA")
with open(rep + "/em.rpt", "w") as f:
    for kind, (u, i, cap, x, y) in sorted(worst.items()):
        f.write(f"{kind:5} worst {i:7.3f} mA of {cap:8.3f} mA ({100 * u:5.1f}%) at ({x:.2f}, {y:.2f})\n")
    rest = sorted((set(metal) | {v[0] for v in via.values()}) - set(worst))
    f.write(f"{' '.join(rest)}: every segment within one minimum-width wire or one cut\n")
    f.writelines(o + "\n" for o in over)
    f.write(f"segments over the limit: {len(over)}\n")
print(open(rep + "/em.rpt").read())
