# KLayout: metal fill on the sky130 fill layers, clear of drawn metal, the seal ring, the I/O cells and the
# SRAMs. Run: klayout -b -r signoff/fill.py
import os
import pya

out = os.environ["OUT"]
ly = pya.Layout()
ly.read(out + "/chip_top.gds")
top = ly.cell("chip_top")
um = lambda v: int(round(v / ly.dbu))

# area inside the seal ring band, less the hard cells with 2 um of room
die = top.bbox_per_layer(ly.layer(235, 4))
area = pya.Region(die).sized(-um(12))
for inst in top.each_inst():
    if inst.cell.name.startswith(("sky130_ef_io__", "sky130_sram_")):
        area -= pya.Region(inst.bbox()).sized(um(2))

# drawn layer, fill layer, square, pitch, room to drawn metal (um)
for (m, fill), size, pitch, room in [
        ((68, 36), 2.0, 4.0, 1.0),
        ((69, 41), 2.0, 4.0, 1.0),
        ((70, 34), 2.0, 4.0, 1.0),
        ((71, 51), 3.0, 6.0, 2.0),
        ((72, 59), 3.0, 6.0, 2.0)]:
    drawn = pya.Region()
    for dt in (20, 16):
        drawn += pya.Region(top.begin_shapes_rec(ly.layer(m, dt)))
    free = area - drawn.sized(um(room))
    cell = ly.create_cell(f"fill_{m}")
    square = pya.Box(0, 0, um(size), um(size))
    cell.shapes(ly.layer(fill, 28)).insert(square)
    top.fill_region(free, cell.cell_index(), square, pya.Vector(um(pitch), 0), pya.Vector(0, um(pitch)),
                    pya.Point(), None, pya.Vector(), None, pya.Box())
    print(f"{m}/20: {free.area() * ly.dbu ** 2 / 1e6:.3f} mm2 free, fill cell {cell.name}")

ly.write(out + "/chip_top.gds")
