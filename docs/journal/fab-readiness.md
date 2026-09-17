# Fab readiness

Spec: [spec_v9.md](../spec_v9.md). The chip is a standalone die, and its GDS has to pass a foundry's own checks with nothing waived. That adds checks the flow did not have: KLayout DRC over the whole GDS with the I/O cells included, electromigration on the power grid, equivalence of the routed netlist, Magic DRC on the full GDS, and the PDK's density windows.

## Pad ring seams

The 34,334 KLayout errors counted as inside the SkyWater I/O cells were checked against the PDK cells on their own. One of each pad cell, placed apart, gives 16 errors. The rest came from how the ring put the cells together:

- `gpiov2` pads abutting: 28,770. Their wells reach past their LEF outline.
- The `vccd` and `vssd` pads: about 3,300. An overlay reaches about 11 µm past the outline onto the neighbour's vias.
- Other seams: about 1,000, at the 1 µm slices and the high-voltage pads.

Rows of PDK cells checked with the same deck give the clean distance for each pair of neighbours: 12 µm between `gpiov2` pads and between a `gpiov2` and a `vccd` or `vssd` pad, 5 µm next to the high-voltage pads. With those gaps the ring needs a 2.35 mm die.

Decision: space the pads by the measured distances on a 2.35 mm die.

