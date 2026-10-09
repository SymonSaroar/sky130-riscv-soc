# A licensed PCIe PHY in place of the placeholder

`pcie_phy` stands for a hard PCIe Gen1 x1 PHY. It has the pins, timing and views such a macro ships with, and an empty layout. A chip that links to a real device needs a licensed 130 nm PHY in its place: the open SKY130 PDK has no SerDes, PLL or line drivers.

## Views

| View | Placeholder (`macros/pcie_phy.py`) | Licensed PHY |
|---|---|---|
| LEF | outline, pins, blockages below met5 | the vendor's abstract, with antenna data |
| Liberty | tt, ss and ff; PIPE setup, hold and clock to output; leakage | the vendor's corners, with power |
| GDS | outline and pins | full layout |
| Verilog | black box; `tb/pcie_phy.v` for simulation | the vendor's simulation model |
| SPICE | empty subcircuit, a black box in LVS | the vendor's netlist for LVS |

The Makefile builds the views as `PHY_VIEWS`. The vendor's files take their place, with the same cell name or a renamed instance in `chip_top.v`.

## PIPE

The MAC side expects PIPE with 32 bits per clock at 62.5 MHz and PCLK as a PHY input: the PHY drives MaxPCLK, and the clock tree takes it to `pcie_pipe.v` and back into the PHY's PCLK pin. A PHY with 16 bits at 125 MHz needs the gearbox from the TI-PIPE front end back in `pcie_pipe.v`. A PHY that drives PCLK as an output needs `create_clock` on that pin and timing arcs related to it.

The PHY must do 8b/10b, the elastic buffer with SKP add and remove, receiver detection and electrical idle. Scrambling stays with the PHY as well; the MAC sends Training Control 00h.

## Pads, supplies and floorplan

- The lane, the reference clock and REXT use `sky130_ef_io__analog_pad`, which is a straight met5 connection without ESD. The PHY's own ESD protects the lane, as the vendor specifies; if the vendor expects ESD in the pad, `analog_esd_pad` replaces it.
- AVDD and AVSS come from `vccd_lvc_clamped3` and `vssd_lvc_clamped3` pads, whose VCCD1 and VSSD1 pins feed the macro. A PHY with more supply domains needs a pair of pads for each, and the vendor's decoupling.
- The macro sits next to its pads. The lane pairs route short, matched in length and shielded, as the vendor's layout guide sets out.
- The reference clock is 100 MHz HCSL. Spread-spectrum clocking works only if the PHY supports it.

## Signoff

- STA with the vendor's liberty at every corner the chip is signed off at.
- LVS with the vendor's netlist in place of the black box. Netgen pairs the bits of a bus port in the order the netlist lists them, so the netlist's bus pins must run in the routed Verilog's order, most significant bit first. DRC on the full GDS, with the vendor's waivers for the macro.
- The vendor's ESD and latch-up rules for the macro and its pads.
- Simulation with the vendor's model behind the same testbench, then the compliance tests the vendor recommends.
