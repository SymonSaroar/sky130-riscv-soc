"""Collect one run's numbers into reports/metrics.csv (one row per run)."""
import collections, csv, fnmatch, os, re, sys

run = sys.argv[1]
rep, out = f"reports/{run}", f"build/{run}"
FIELDS = ["run", "clock_ns", "wns_ns", "tns_ns", "whs_ns", "viol_endpoints", "hold_viol", "slew_viol", "slew_waived", "cap_viol", "fmax_mhz", "wns_mclk_ns", "fmax_mclk_mhz", "wns_pclk_ns", "fmax_pclk_mhz", "wns_ss_ns", "fmax_ss_mhz", "fmax_mclk_ss_mhz", "whs_ff_ns", "hold_viol_ff", "die_um", "util_pct", "place_density",
          "power_mw", "ir_drop_mv", "grt_congestion", "route_drc", "antenna_nets", "magic_drc", "klayout_drc", "klayout_drc_waived", "density", "lvs"]


def read(path):
    return open(path).read() if os.path.exists(path) else ""


def grab(pattern, text, default=""):
    m = re.findall(pattern, text)
    return m[-1] if m else default


row = {"run": run}
row["clock_ns"] = "/".join(re.findall(r"-period\s+([\d.]+)", read("constraints/soc.sdc")))
sta = dict(l.split() for l in read(f"{rep}/sta.summary").splitlines())
row.update(wns_ns=sta.get("wns", ""), tns_ns=sta.get("tns", ""), whs_ns=sta.get("whs", ""),
           viol_endpoints=sta.get("viol_endpoints", ""), hold_viol=sta.get("hold_viol_endpoints", ""), wns_mclk_ns=sta.get("wns_mclk", ""),
           fmax_mclk_mhz=sta.get("fmax_mclk_mhz", ""), wns_pclk_ns=sta.get("wns_pclk", ""),
           fmax_pclk_mhz=sta.get("fmax_pclk_mhz", ""),
           fmax_mhz=sta.get("fmax_mhz", ""))
# slow corner setup and fast corner hold
ss = dict(l.split() for l in read(f"{rep}/sta_ss.summary").splitlines())
ff = dict(l.split() for l in read(f"{rep}/sta_ff.summary").splitlines())
row.update(wns_ss_ns=ss.get("wns", ""), fmax_ss_mhz=ss.get("fmax_mhz", ""), fmax_mclk_ss_mhz=ss.get("fmax_mclk_mhz", ""),
           whs_ff_ns=ff.get("whs", ""), hold_viol_ff=ff.get("hold_viol_endpoints", ""))
drv = read(f"{rep}/sta.drv.rpt")
waivers = [l.split()[:2] for l in read("signoff/waivers.txt").splitlines() if l.strip() and not l.startswith("#")]
for key, sec, check in (("slew_viol", "max slew", "max_slew"), ("cap_viol", "max capacitance", "max_cap")):
    part = re.split(r"\n(?=max (?:slew|capacitance|fanout)\n)", "\n" + drv)
    body = part and [x for x in part if x.startswith(sec)]
    pins = [l.split()[0] for l in (body[0].splitlines() if body else []) if "VIOLATED" in l]
    waived = [p for p in pins if any(c == check and fnmatch.fnmatch(p, pat) for c, pat in waivers)]
    row[key] = str(len(pins) - len(waived)) if drv else ""
    if key == "slew_viol":
        row["slew_waived"] = str(len(waived)) if drv else ""
die = grab(r"DIEAREA \( 0 0 \) \( (\d+) (\d+) \)", read(f"{out}/chip_top.def"), ())
row["die_um"] = f"{int(die[0]) / 1000:.0f}x{int(die[1]) / 1000:.0f}" if die else ""
row["place_density"] = grab(r"Placement target density:\s+([\d.]+)", read(f"{out}/place.log"))
row["util_pct"] = grab(r"Design area \d+ um\^2 (\d+)% utilization", read(f"{out}/cts.log"))
total = re.findall(r"^Total\s+\S+\s+\S+\s+\S+\s+(\S+)", read(f"{rep}/power.rpt"), re.M)
# core power: the design total less the pad cells listed after it
pads = re.findall(r"^\s*\S+\s+\S+\s+\S+\s+(\S+)\s+p_\w+\.p$", read(f"{rep}/power.rpt"), re.M)
row["power_mw"] = f"{(float(total[0]) - sum(map(float, pads))) * 1e3:.2f}" if total else ""
ir = [float(x) for x in re.findall(r"Worstcase IR drop:\s+([\d.eE+-]+)", read(f"{rep}/ir.rpt"))]
row["ir_drop_mv"] = f"{max(ir) * 1e3:.2f}" if ir else ""
row["grt_congestion"] = str(read(f"{rep}/congestion.rpt").count("violation type")) if os.path.exists(f"{out}/route.log") else ""
row["route_drc"] = str(read(f"{rep}/route_drc.rpt").count("violation type")) if os.path.exists(f"{rep}/route_drc.rpt") else ""
row["antenna_nets"] = grab(r"Found (\d+) net violations", read(f"{out}/finish.log") or read(f"{out}/route.log"))
kl = read(f"{rep}/drc_klayout.xml")
# KLayout errors inside the SkyWater I/O cells are counted apart
io_boxes = []
lef = read(os.environ.get("PDK_ROOT", os.path.expanduser("~/.volare")) + "/sky130A/libs.ref/sky130_fd_io/lef/sky130_ef_io.lef")
size = {m[0]: (float(m[1]), float(m[2])) for m in re.findall(r"MACRO (\S+)\s.*?SIZE ([\d.]+) BY ([\d.]+)", lef, re.S)}
for name, master, x, y, o in re.findall(r"- (\S+) (sky130_ef_io__\S+) \+ \w+ \( (\d+) (\d+) \) (\S+)", read(f"{out}/chip_top.def")):
    w, h = size[master][::-1] if o in ("E", "W", "FE", "FW") else size[master]
    io_boxes.append((int(x) / 1000 - 0.5, int(y) / 1000 - 0.5, int(x) / 1000 + w + 0.5, int(y) / 1000 + h + 0.5))
kl_items = re.findall(r"<item>.*?<category>'?([^<']+)'?</category>.*?<cell>([^<:]*).*?<values>(.*?)</values>", kl, re.S)
by_rule = collections.Counter()
for rule, cell, v in kl_items:
    # items inside a cell carry that cell's coordinates; top-level items are placed against the pad boxes
    if cell != "chip_top":
        by_rule[rule, cell.startswith(("sky130_ef_io__", "sky130_fd_io__"))] += 1
        continue
    xy = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", v.split(":", 1)[-1])]
    cx, cy = (min(xy[0::2]) + max(xy[0::2])) / 2, (min(xy[1::2]) + max(xy[1::2])) / 2
    by_rule[rule, any(x0 <= cx <= x1 and y0 <= cy <= y1 for x0, y0, x1, y1 in io_boxes)] += 1
kl_io = sum(n for (_, io), n in by_rule.items() if io)
row["klayout_drc"] = str(len(kl_items) - kl_io) if kl else ""
# Magic reads the pad cells as LEF abstracts; errors within 2 um of a pad cell are on that abstract geometry
magic = read(f"{rep}/drc_magic.rpt")
boxes = [tuple(map(float, l.split("\t")[1].split())) for l in magic.splitlines() if l.count("\t") == 1 and len(l.split("\t")[1].split()) == 4]
on_io = sum(any(x0 - 1.5 <= a and c <= x1 + 1.5 and y0 - 1.5 <= b and d <= y1 + 1.5 for x0, y0, x1, y1 in io_boxes) for a, b, c, d in boxes)
row["magic_drc"] = str(len(boxes) - on_io) if boxes else grab(r"total (\d+)", magic)
row["klayout_drc_waived"] = str(kl_io) if kl else ""
if kl:
    with open(f"{rep}/drc_klayout.summary", "w") as f:
        f.write("rule outside_io_cells inside_io_cells\n")
        for rule in sorted({r for r, _ in by_rule}):
            f.write(f"{rule} {by_rule[rule, False]} {by_rule[rule, True]}\n")
# PDK pattern density deck
dens = read(f"{rep}/density.xml")
row["density"] = ("clean" if dens.count("<item>") == 0 else str(dens.count("<item>"))) if dens else ""
lvs = read(f"{rep}/lvs.summary")
row["lvs"] = "" if not lvs else "clean" if "Circuits match uniquely" in lvs else "mismatch"

path = "reports/metrics.csv"
rows = list(csv.DictReader(open(path))) if os.path.exists(path) else []
rows = sorted([r for r in rows if r["run"] != run] + [row], key=lambda r: (int(re.match(r"\d+", r["run"]).group()), r["run"]))
with open(path, "w", newline="") as f:
    w = csv.DictWriter(f, FIELDS)
    w.writeheader()
    w.writerows(rows)
print(row)

# README results table, between the metrics markers
cols = ["run", "place_density", "wns_ns", "tns_ns", "whs_ns", "viol_endpoints", "hold_viol", "fmax_mhz", "wns_mclk_ns", "fmax_mclk_mhz", "wns_pclk_ns", "fmax_pclk_mhz", "wns_ss_ns", "fmax_ss_mhz", "fmax_mclk_ss_mhz", "whs_ff_ns", "hold_viol_ff", "slew_viol", "slew_waived", "cap_viol",
        "antenna_nets", "power_mw", "ir_drop_mv", "grt_congestion", "route_drc", "magic_drc", "klayout_drc", "klayout_drc_waived", "density", "lvs"]
table = "| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n"
table += "".join("| " + " | ".join(r.get(c) or "-" for c in cols) + " |\n" for r in rows)
readme = read("README.md")
if "<!-- metrics -->" in readme:
    head, rest = readme.split("<!-- metrics -->", 1)
    tail = rest.split("<!-- /metrics -->", 1)[1]
    open("README.md", "w").write(f"{head}<!-- metrics -->\n{table}<!-- /metrics -->{tail}")
