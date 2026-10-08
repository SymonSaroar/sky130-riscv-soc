# PCIe PHY placeholder: the views of a hard PHY macro from one pin table. LEF, liberty for tt/ss/ff, GDS with the
# outline and the pins, a Verilog black box and a SPICE subcircuit.
# Run: klayout -b -r macros/pcie_phy.py -rd out=<dir>
import pya

W, H = 800.0, 800.0
NAME = "pcie_phy"
# PIPE on the north edge, lane and analog pins on the south edge, supplies as met4 stripes
PIPE_IN = [("pclk", 1), ("reset_n", 1), ("tx_data", 32), ("tx_datak", 4), ("tx_elecidle", 1), ("tx_compliance", 1),
           ("tx_detectrx_loopback", 1), ("rx_polarity", 1), ("powerdown", 2)]
PIPE_OUT = [("max_pclk", 1), ("rx_data", 32), ("rx_datak", 4), ("rx_valid", 1), ("rx_status", 3), ("rx_elecidle", 1),
            ("phy_status", 1)]
LANE = [("txp", "output"), ("txn", "output"), ("rxp", "input"), ("rxn", "input"), ("refclk_p", "input"),
        ("refclk_n", "input"), ("rext", "inout")]
SUPPLY = [("vccd", "POWER"), ("vssd", "GROUND"), ("avdd", "POWER"), ("avss", "GROUND")]
# typical-corner PIPE timing (ns); the slow and fast corners scale like the SRAM's liberty
T_SETUP, T_HOLD, T_CQ, T_TR = 1.0, 0.5, 1.5, 0.2
SCALE = {"tt": 1.0, "ss": 2.1, "ff": 0.64}
LIB_NAME = {"tt": "tt_025C_1v80", "ss": "ss_100C_1v60", "ff": "ff_n40C_1v95"}
LEAKAGE_NW = 10e6                 # 10 mW on VCCD
LAYER = {"met2": (69, 20, 16, 5), "met4": (71, 20, 16, 5)}
BOUNDARY = (235, 4)

def bits(name, n):
    return [name] if n == 1 else [f"{name}[{i}]" for i in range(n)]


pipe_pins = [(p, "input") for name, n in PIPE_IN for p in bits(name, n)] + \
            [(p, "output") for name, n in PIPE_OUT for p in bits(name, n)]

# pin rectangles (x0, y0, x1, y1) in um
rects = {}
pitch = 5.0
x = (W - pitch * (len(pipe_pins) - 1)) / 2
for p, _ in pipe_pins:
    rects[p] = ("met2", [(x - 0.14, H - 2.0, x + 0.14, H)])
    x += pitch
x = (W - 60.0 * (len(LANE) - 1)) / 2
for p, _ in LANE:
    rects[p] = ("met2", [(x - 1.0, 0.0, x + 1.0, 4.0)])
    x += 60.0
for i, (p, _) in enumerate(SUPPLY):
    rects[p] = ("met4", [(x0 + 12.0 * i, 10.0, x0 + 12.0 * i + 6.0, H - 10.0) for x0 in range(40, int(W) - 60, 100)])


def lef():
    s = [f"VERSION 5.7 ;\nBUSBITCHARS \"[]\" ;\nDIVIDERCHAR \"/\" ;\nMACRO {NAME}\n  CLASS BLOCK ;\n"
         f"  ORIGIN 0 0 ;\n  FOREIGN {NAME} 0 0 ;\n  SIZE {W:.3f} BY {H:.3f} ;\n  SYMMETRY X Y R90 ;"]
    dirs = dict(pipe_pins + LANE)
    for p, use in [(p, None) for p, _ in pipe_pins] + [(p, None) for p, _ in LANE] + SUPPLY:
        layer, rs = rects[p]
        d = "INOUT" if use else dirs[p].upper()
        s.append(f"  PIN {p}\n    DIRECTION {d} ;\n    USE {use or ('CLOCK' if p in ('pclk', 'max_pclk') else 'SIGNAL')} ;")
        s.append("    PORT")
        for r in rs:
            s.append(f"      LAYER {layer} ;\n        RECT {r[0]:.3f} {r[1]:.3f} {r[2]:.3f} {r[3]:.3f} ;")
        s.append(f"    END\n  END {p}")
    # blocked below met5 apart from the pins: met2 clear of the pin rows, met4 between the stripes
    s.append("  OBS")
    for layer in ("li1", "met1", "met3"):
        s.append(f"    LAYER {layer} ;\n      RECT 0.000 0.000 {W:.3f} {H:.3f} ;")
    s.append(f"    LAYER met2 ;\n      RECT 0.000 6.000 {W:.3f} {H - 4.0:.3f} ;")
    xs = sorted(r for p, _ in SUPPLY for r in rects[p][1])
    s.append("    LAYER met4 ;")
    edge = 0.0
    for r in xs:
        if r[0] - edge > 1.0:
            s.append(f"      RECT {edge:.3f} 0.000 {r[0] - 1.0:.3f} {H:.3f} ;")
        edge = r[2] + 1.0
    s.append(f"      RECT {edge:.3f} 0.000 {W:.3f} {H:.3f} ;")
    s.append(f"  END\nEND {NAME}\n\nEND LIBRARY\n")
    return "\n".join(s)


def lib(corner):
    k = SCALE[corner]
    val = lambda v: f'values("{v:.4f}");'
    s = [f"library ({NAME}_{LIB_NAME[corner]}) {{",
         '  delay_model : table_lookup;\n  time_unit : "1ns";\n  voltage_unit : "1V";\n  current_unit : "1mA";',
         '  pulling_resistance_unit : "1kohm";\n  leakage_power_unit : "1nW";\n  capacitive_load_unit (1, pf);',
         "  input_threshold_pct_rise : 50;\n  input_threshold_pct_fall : 50;\n  output_threshold_pct_rise : 50;",
         "  output_threshold_pct_fall : 50;\n  slew_lower_threshold_pct_rise : 20;\n  slew_lower_threshold_pct_fall : 20;",
         "  slew_upper_threshold_pct_rise : 80;\n  slew_upper_threshold_pct_fall : 80;",
         f"  nom_voltage : {1.8 if corner == 'tt' else 1.6 if corner == 'ss' else 1.95};"]
    for n in sorted({n for _, n in PIPE_IN + PIPE_OUT if n > 1}):
        s.append(f"  type (bus{n}) {{\n    base_type : array;\n    data_type : bit;\n    bit_width : {n};"
                 f"\n    bit_from : {n - 1};\n    bit_to : 0;\n    downto : true;\n  }}")
    s.append(f"  cell ({NAME}) {{\n    area : {W * H:.1f};\n    is_macro_cell : true;\n    dont_touch : true;"
             f"\n    dont_use : true;\n    interface_timing : true;\n    cell_leakage_power : {LEAKAGE_NW:.1f};")
    for (name, n), d in [(x, "input") for x in PIPE_IN] + [(x, "output") for x in PIPE_OUT]:
        head = f'    pin ({name}) {{' if n == 1 else f'    bus ({name}) {{\n      bus_type : bus{n};'
        s.append(f"{head}\n      direction : {d};")
        if name == "pclk":
            s.append("      clock : true;\n      capacitance : 0.020;")
        elif name == "max_pclk":
            s.append("      clock : true;")
        elif d == "input":
            s.append("      capacitance : 0.005;")
            for kind, v in (("setup_rising", T_SETUP * (k if corner == "ss" else 1.0)), ("hold_rising", T_HOLD)):
                s.append(f'      timing () {{\n        related_pin : "pclk";\n        timing_type : {kind};'
                         f"\n        rise_constraint (scalar) {{ {val(v)} }}"
                         f"\n        fall_constraint (scalar) {{ {val(v)} }}\n      }}")
        else:
            s.append(f'      timing () {{\n        related_pin : "pclk";\n        timing_type : rising_edge;'
                     f"\n        cell_rise (scalar) {{ {val(T_CQ * k)} }}\n        cell_fall (scalar) {{ {val(T_CQ * k)} }}"
                     f"\n        rise_transition (scalar) {{ {val(T_TR * k)} }}"
                     f"\n        fall_transition (scalar) {{ {val(T_TR * k)} }}\n      }}")
        s.append("    }")
    for p, d in LANE:
        s.append(f"    pin ({p}) {{\n      direction : {d};\n      capacitance : 0.0;\n    }}")
    s.append("  }\n}\n")
    return "\n".join(s)


def ports():
    return [p for p, _ in pipe_pins] + [p for p, _ in LANE]


def verilog():
    decl = []
    for name, n in PIPE_IN:
        decl.append(f"  input {'' if n == 1 else f'[{n - 1}:0] '}{name};")
    for name, n in PIPE_OUT:
        decl.append(f"  output {'' if n == 1 else f'[{n - 1}:0] '}{name};")
    for p, d in LANE:
        decl.append(f"  {d} {p};")
    names = [name for name, _ in PIPE_IN + PIPE_OUT] + [p for p, _ in LANE]
    pw = ", ".join(p for p, _ in SUPPLY)
    return (f"// {NAME} black box\n(* blackbox *)\nmodule {NAME} (\n`ifdef USE_POWER_PINS\n  {pw},\n`endif\n  "
            + ", ".join(names) + "\n);\n`ifdef USE_POWER_PINS\n" + "".join(f"  inout {p};\n" for p, _ in SUPPLY)
            + "`endif\n" + "\n".join(decl) + "\nendmodule\n")


def spice():
    pins = ports() + [p for p, _ in SUPPLY]
    lines, cur = [], f".subckt {NAME}"
    for p in pins:
        if len(cur) + len(p) > 100:
            lines.append(cur)
            cur = "+"
        cur += " " + p
    lines.append(cur)
    return "\n".join(lines) + f"\n.ends {NAME}\n"


def gds(path):
    ly = pya.Layout()
    ly.dbu = 0.001
    c = ly.create_cell(NAME)
    c.shapes(ly.layer(*BOUNDARY)).insert(pya.DBox(0, 0, W, H))
    for p, (layer, rs) in rects.items():
        num, drw, pin, lbl = LAYER[layer]
        for r in rs:
            box = pya.DBox(*r)
            c.shapes(ly.layer(num, drw)).insert(box)
            c.shapes(ly.layer(num, pin)).insert(box)
            c.shapes(ly.layer(num, lbl)).insert(pya.DText(p, pya.DTrans(box.center().x, box.center().y)))
    ly.write(path)


open(f"{out}/{NAME}.lef", "w").write(lef())
for corner in SCALE:
    open(f"{out}/{NAME}_{corner}.lib", "w").write(lib(corner))
open(f"{out}/{NAME}.v", "w").write(verilog())
open(f"{out}/{NAME}.spice", "w").write(spice())
gds(f"{out}/{NAME}.gds")
