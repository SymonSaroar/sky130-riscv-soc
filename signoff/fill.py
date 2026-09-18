# KLayout: fill on every layer from the PDK fill generator (Magic wafflefill), clear of the seal ring, the I/O
# cells and the SRAMs. Run: klayout -b -r signoff/fill.py
import os
import subprocess
import pya

pdk = os.environ["PDK_ROOT"] + "/sky130A"
out = os.environ["OUT"]
work = out + "/fill"
ly = pya.Layout()
ly.read(out + "/chip_top.gds")
top = ly.cell("chip_top")
um = lambda v: int(round(v / ly.dbu))

# the generator fills what the fill-block layers (datatype 98) leave open
die = top.bbox_per_layer(ly.layer(235, 4))
keep = die.enlarged(-um(12), -um(12))
block = pya.Region(top.bbox().enlarged(um(10), um(10))) - pya.Region(keep)
sram = pya.Region()
for inst in top.each_inst():
    if inst.cell.name.startswith("sky130_ef_io__"):
        block += pya.Region(inst.bbox()).sized(um(2))
    elif inst.cell.name.startswith("sky130_sram_"):
        sram += pya.Region(inst.bbox()).sized(um(2))
# the SRAMs block diffusion, li and met1 to met3, the layers their LEF obstructs
blocks = [ly.layer(n, 98) for n in (65, 67, 68, 69, 70, 71, 72)]
for li in blocks:
    top.shapes(li).insert((block + (sram if ly.get_info(li).layer <= 70 else pya.Region())).merged())
os.makedirs(work, exist_ok=True)
ly.write(work + "/chip_top.gds")
for li in blocks:
    top.shapes(li).clear()
subprocess.run(["python3", pdk + "/libs.tech/magic/generate_fill.py", "chip_top.gds"], cwd=work,
               env=dict(os.environ, PDK="sky130A"), check=True)

# the generator tiles past the die; only fill wholly inside the kept area stays
ly.read(work + "/chip_top_fill_pattern.gds.gz")
fill = ly.cell("chip_top_fill_pattern")
total = 0
for ci in [fill.cell_index()] + list(fill.each_child_cell()):
    cell = ly.cell(ci)
    for li in ly.layer_indices():
        if cell.shapes(li).is_empty():
            continue
        r = pya.Region(cell.shapes(li))
        r.merged_semantics = False
        inside = r.inside(pya.Region(keep))
        cell.shapes(li).clear()
        cell.shapes(li).insert(inside)
        total += inside.count()
top.insert(pya.CellInstArray(fill.cell_index(), pya.Trans()))
ly.write(out + "/chip_top.gds")
print(f"{total} fill shapes")
