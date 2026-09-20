# KLayout: DEF + cell GDS -> final GDS. Run: klayout -b -r signoff/def2gds.py
import os
import pya

pdk = os.environ["PDK_ROOT"] + "/sky130A"
out = os.environ["OUT"]
sc, sm, io = pdk + "/libs.ref/sky130_fd_sc_hd", pdk + "/libs.ref/sky130_sram_macros", pdk + "/libs.ref/sky130_fd_io"
sram = "sky130_sram_2kbyte_1rw1r_32x512_8"

tech = pya.Technology()
tech.load(pdk + "/libs.tech/klayout/tech/sky130A.lyt")
opt = tech.load_layout_options
cfg = opt.lefdef_config
cfg.map_file = pdk + "/libs.tech/klayout/tech/sky130A.map"
cfg.lef_files = [sc + "/techlef/sky130_fd_sc_hd__nom.tlef", sc + "/lef/sky130_fd_sc_hd.lef", f"{sm}/lef/{sram}.lef",
                 io + "/lef/sky130_ef_io.lef"]
cfg.produce_pin_names = True

ly = pya.Layout()
ly.read(out + "/chip_top.def", opt)
top = ly.cell("chip_top")
for c in ly.each_cell():
    if c.cell_index() != top.cell_index() and not c.name.startswith("VIA"):
        c.clear()
ly.read(sc + "/gds/sky130_fd_sc_hd.gds")
ly.read(f"{sm}/gds/{sram}.gds")
# pads: the sky130_ef_io cells reference sky130_fd_io cells as empty placeholders
for g in ["sky130_ef_io", "sky130_fd_io", "sky130_ef_io__gpiov2_pad_wrapped",
          "sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um"]:
    ly.read(f"{io}/gds/{g}.gds")

final = pya.Layout()
final.dbu = ly.dbu
final.create_cell("chip_top").copy_tree(top)
final.write(out + "/chip_top.gds")
