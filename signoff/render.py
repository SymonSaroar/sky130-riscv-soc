# KLayout: render the final GDS to a PNG. Run: klayout -b -r signoff/render.py
import os
import pya

out = os.environ["OUT"]
layers = [("li1", "67/20", 0x9e9e9e), ("met1", "68/20", 0x2f6fdf), ("met2", "69/20", 0xd23fd2),
          ("met3", "70/20", 0x1fb5a8), ("met4", "71/20", 0xd6a51c), ("met5", "72/20", 0xe0582a)]

view = pya.LayoutView()
view.load_layout(out + "/chip_top.gds", False)
view.clear_layers()
for name, src, color in layers:
    lp = pya.LayerPropertiesNode()
    lp.name, lp.source = name, src + "@1"
    lp.fill_color = lp.frame_color = color
    lp.dither_pattern = 5
    lp.width = 0
    view.insert_layer(view.end_layers(), lp)
view.max_hier()
view.set_config("background-color", "#101418")
view.zoom_fit()
view.save_image_with_options(os.environ["REP"] + "/layout.png", 1400, 1400, 0, 0, 0, pya.DBox(), False)
