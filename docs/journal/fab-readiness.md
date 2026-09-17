# Fab readiness

Spec: [spec_v9.md](../spec_v9.md). The chip is a standalone die, and its GDS has to pass a foundry's own checks with nothing waived. That adds checks the flow did not have: KLayout DRC over the whole GDS with the I/O cells included, electromigration on the power grid, equivalence of the routed netlist, Magic DRC on the full GDS, and the PDK's density windows.

| Change | Die (mm) | Setup WNS clk / mclk, tt (ns) | Setup WNS clk / mclk, ss (ns) | Hold WNS tt / ff (ns) | KLayout DRC |
| Pads spaced by measured distances | 2.35 | +0.99 / +0.50 | +1.97 / +1.59 | +0.181 / +0.016 | 0 |
| 3.2 µm met4 and met5 stripes | 2.35 | +0.98 / +0.51 | +1.94 / +1.60 | +0.168 / +0.013 | 0 |

## Pad ring seams

The 34,334 KLayout errors counted as inside the SkyWater I/O cells were checked against the PDK cells on their own. One of each pad cell, placed apart, gives 16 errors. The rest came from how the ring put the cells together:

- `gpiov2` pads abutting: 28,770. Their wells reach past their LEF outline.
- The `vccd` and `vssd` pads: about 3,300. An overlay reaches about 11 µm past the outline onto the neighbour's vias.
- Other seams: about 1,000, at the 1 µm slices and the high-voltage pads.

Rows of PDK cells checked with the same deck give the clean distance for each pair of neighbours: 12 µm between `gpiov2` pads and between a `gpiov2` and a `vccd` or `vssd` pad, 5 µm next to the high-voltage pads. With those gaps the ring needs a 2.35 mm die.

Decision: space the pads by the measured distances on a 2.35 mm die.

## Spaced pads

![layout](../../reports/45-pad-spacing/layout.png)

KLayout finds no error on the whole GDS, pad cells included, and nothing is waived. Timing closes at all three corners; IR drop is 19.9 mV.

PDNSim's segment currents, checked against the average-current limits in the tech LEF (90 °C), pass on every wire. Two via4 crossings carry 2.96 and 3.09 mA per cut against 2.49 mA.

Decision: widen the met4 and met5 stripes from 1.6 to 3.2 µm.

