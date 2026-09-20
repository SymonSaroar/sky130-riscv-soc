# Bond pad list: every pad opening with its pin or supply, numbered counter-clockwise from the south-west corner.
import os, re
import pya

pdk = os.environ["PDK_ROOT"] + "/sky130A"
out, rep = os.environ["OUT"], os.environ["REP"]
lef = open(pdk + "/libs.ref/sky130_fd_io/lef/sky130_ef_io.lef").read()
size = {m[0]: (float(m[1]), float(m[2])) for m in re.findall(r"MACRO (\S+)\s.*?SIZE ([\d.]+) BY ([\d.]+)", lef, re.S)}
supply = {"vccd": ("VCCD", "1.8 V core"), "vssd": ("VSSD", "core ground"), "vddio": ("VDDIO", "3.3 V I/O"),
          "vssio": ("VSSIO", "I/O ground"), "vdda": ("VDDA", "3.3 V analog"), "vssa": ("VSSA", "analog ground")}

d = open(out + "/chip_top.def").read()
die = int(re.search(r"DIEAREA \( 0 0 \) \( (\d+) \d+ \)", d)[1]) / 1000
pin = {inst: name.replace("\\", "") for name, inst in re.findall(r"\( PIN (\S+) \) \( (p_\S+) PAD \)", d)}
direction = {n.replace("\\", ""): v.lower() for n, v in re.findall(r"- (\S+) \+ NET \S+ (?:\+ SPECIAL )?\+ DIRECTION (\w+)", d)}
inst = {}
for name, master, x, y in re.findall(r"- (\S+) (sky130_ef_io__\S+) \+ FIXED \( (\d+) (\d+) \)", d):
    inst[int(x), int(y)] = name

ly = pya.Layout()
ly.read(out + "/chip_top.gds")
top = ly.cell("chip_top")
opening = ly.find_layer(76, 20)
rows = []
for i in top.each_inst():
    if not i.cell.name.startswith("sky130_ef_io__"):
        continue
    reg = pya.Region(i.cell.begin_shapes_rec(opening)).transformed(i.cplx_trans).merged()
    if reg.is_empty():
        continue
    box = pya.DBox(0, 0, *size[i.cell.name]).transformed(i.dcplx_trans)
    name = inst[round(box.left * 1000), round(box.bottom * 1000)]
    b = reg.bbox().to_dtype(ly.dbu)
    c = b.center()
    side = min((c.y, "south"), (die - c.x, "east"), (die - c.y, "north"), (c.x, "west"))[1]
    if name in pin:
        net, kind = pin[name], direction[pin[name]]
    else:
        net, kind = supply[name.split("_")[0]]
    order = {"south": c.x, "east": die + c.y, "north": 3 * die - c.x, "west": 4 * die - c.y}[side]
    rows.append((order, net, kind, side, c.x, c.y, b.width(), b.height(), i.cell.name))
rows.sort()
with open(rep + "/pads.csv", "w") as f:
    f.write("pad,net,type,side,x_um,y_um,opening_w_um,opening_h_um,cell\n")
    for n, (_, net, kind, side, x, y, w, h, cell) in enumerate(rows, 1):
        f.write(f"{n},{net},{kind},{side},{x:.3f},{y:.3f},{w:.3f},{h:.3f},{cell}\n")
print(len(rows), "pads")
