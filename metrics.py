"""Collect one run's numbers into reports/metrics.csv (one row per run)."""
import csv, os, re, sys

run = sys.argv[1]
rep, out = f"reports/{run}", f"build/{run}"
FIELDS = ["run", "clock_ns", "wns_ns", "tns_ns", "whs_ns", "fmax_mhz", "die_um", "util_pct",
          "power_mw", "route_drc", "antenna_nets", "magic_drc", "klayout_drc", "lvs"]


def read(path):
    return open(path).read() if os.path.exists(path) else ""


def grab(pattern, text, default=""):
    m = re.findall(pattern, text)
    return m[-1] if m else default


row = {"run": run}
row["clock_ns"] = grab(r"-period\s+([\d.]+)", read("constraints/soc.sdc"))
sta = dict(l.split() for l in read(f"{rep}/sta.summary").splitlines())
row.update(wns_ns=sta.get("wns", ""), tns_ns=sta.get("tns", ""), whs_ns=sta.get("whs", ""),
           fmax_mhz=sta.get("fmax_mhz", ""))
die = grab(r"DIEAREA \( 0 0 \) \( (\d+) (\d+) \)", read(f"{out}/soc_top.def"), ())
row["die_um"] = f"{int(die[0]) / 1000:.0f}x{int(die[1]) / 1000:.0f}" if die else ""
row["util_pct"] = grab(r"Design area \d+ um\^2 (\d+)% utilization", read(f"{out}/cts.log"))
total = re.findall(r"^Total\s+\S+\s+\S+\s+\S+\s+(\S+)", read(f"{rep}/power.rpt"), re.M)
row["power_mw"] = f"{float(total[0]) * 1e3:.2f}" if total else ""
row["route_drc"] = str(read(f"{rep}/route_drc.rpt").count("violation type")) if os.path.exists(f"{rep}/route_drc.rpt") else ""
row["antenna_nets"] = grab(r"Found (\d+) net violations", read(f"{out}/route.log"))
row["magic_drc"] = grab(r"total (\d+)", read(f"{rep}/drc_magic.rpt"))
kl = read(f"{rep}/drc_klayout.xml")
row["klayout_drc"] = str(kl.count("<item>")) if kl else ""
lvs = read(f"{rep}/lvs.summary")
row["lvs"] = "" if not lvs else "clean" if "Circuits match uniquely" in lvs else "mismatch"

path = "reports/metrics.csv"
rows = list(csv.DictReader(open(path))) if os.path.exists(path) else []
rows = [r for r in rows if r["run"] != run] + [row]
with open(path, "w", newline="") as f:
    w = csv.DictWriter(f, FIELDS)
    w.writeheader()
    w.writerows(rows)
print(row)
