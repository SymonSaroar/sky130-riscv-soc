"""Collect one run's numbers into reports/metrics.csv (one row per run)."""
import csv, fnmatch, os, re, sys

run = sys.argv[1]
rep, out = f"reports/{run}", f"build/{run}"
FIELDS = ["run", "clock_ns", "wns_ns", "tns_ns", "whs_ns", "viol_endpoints", "hold_viol", "slew_viol", "slew_waived", "cap_viol", "fmax_mhz", "wns_mclk_ns", "fmax_mclk_mhz", "die_um", "util_pct", "place_density",
          "power_mw", "ir_drop_mv", "grt_congestion", "route_drc", "antenna_nets", "magic_drc", "klayout_drc", "lvs"]


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
           fmax_mclk_mhz=sta.get("fmax_mclk_mhz", ""),
           fmax_mhz=sta.get("fmax_mhz", ""))
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
die = grab(r"DIEAREA \( 0 0 \) \( (\d+) (\d+) \)", read(f"{out}/soc_top.def"), ())
row["die_um"] = f"{int(die[0]) / 1000:.0f}x{int(die[1]) / 1000:.0f}" if die else ""
row["place_density"] = grab(r"Placement target density:\s+([\d.]+)", read(f"{out}/place.log"))
row["util_pct"] = grab(r"Design area \d+ um\^2 (\d+)% utilization", read(f"{out}/cts.log"))
total = re.findall(r"^Total\s+\S+\s+\S+\s+\S+\s+(\S+)", read(f"{rep}/power.rpt"), re.M)
row["power_mw"] = f"{float(total[0]) * 1e3:.2f}" if total else ""
ir = [float(x) for x in re.findall(r"Worstcase IR drop:\s+([\d.eE+-]+)", read(f"{rep}/ir.rpt"))]
row["ir_drop_mv"] = f"{max(ir) * 1e3:.2f}" if ir else ""
row["grt_congestion"] = str(read(f"{rep}/congestion.rpt").count("violation type")) if os.path.exists(f"{out}/route.log") else ""
row["route_drc"] = str(read(f"{rep}/route_drc.rpt").count("violation type")) if os.path.exists(f"{rep}/route_drc.rpt") else ""
row["antenna_nets"] = grab(r"Found (\d+) net violations", read(f"{out}/finish.log") or read(f"{out}/route.log"))
row["magic_drc"] = grab(r"total (\d+)", read(f"{rep}/drc_magic.rpt"))
kl = read(f"{rep}/drc_klayout.xml")
row["klayout_drc"] = str(kl.count("<item>")) if kl else ""
lvs = read(f"{rep}/lvs.summary")
row["lvs"] = "" if not lvs else "clean" if "Circuits match uniquely" in lvs else "mismatch"

path = "reports/metrics.csv"
rows = list(csv.DictReader(open(path))) if os.path.exists(path) else []
rows = sorted([r for r in rows if r["run"] != run] + [row], key=lambda r: r["run"])
with open(path, "w", newline="") as f:
    w = csv.DictWriter(f, FIELDS)
    w.writeheader()
    w.writerows(rows)
print(row)

# README results table, between the metrics markers
cols = ["run", "place_density", "wns_ns", "tns_ns", "whs_ns", "viol_endpoints", "hold_viol", "fmax_mhz", "wns_mclk_ns", "fmax_mclk_mhz", "slew_viol", "slew_waived", "cap_viol",
        "antenna_nets", "power_mw", "ir_drop_mv", "grt_congestion", "route_drc", "magic_drc", "klayout_drc", "lvs"]
table = "| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n"
table += "".join("| " + " | ".join(r.get(c) or "-" for c in cols) + " |\n" for r in rows)
readme = read("README.md")
if "<!-- metrics -->" in readme:
    head, rest = readme.split("<!-- metrics -->", 1)
    tail = rest.split("<!-- /metrics -->", 1)[1]
    open("README.md", "w").write(f"{head}<!-- metrics -->\n{table}<!-- /metrics -->{tail}")
