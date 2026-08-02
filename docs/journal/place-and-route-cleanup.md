# Place and route cleanup

Starting point: the external memory design. Timing and hold close, DRC and LVS are clean, 74 nets have antenna violations, and the die is 923 x 923 µm with standard cells filling about a fifth of it.

| Change | Die (µm) | Antenna nets | Setup WNS clk / mclk (ns) | Hold WNS (ns) | DRC / LVS |
|---|---|---|---|---|---|
| Antenna repair after detailed routing | 923 x 923 | 0 | +4.51 / +2.14 | +0.074 | clean |
| Core utilization 50% to 60% | 844 x 844 | 2 | +4.69 / +1.97 | +0.069 | clean |
| Up to 12 antenna passes | | | | | |

## Antenna repair after detailed routing

The 74 violations are all side-area ratio checks: met2 41, met1 29, met3 19, met4 2. The median net is 1.27 times over the limit and the worst 8.4 times. The flow repairs antennas on the global routes, and detailed routing then lays different wires.

After detailed routing, the flow now checks antennas, inserts diodes on the violating nets, and reroutes only the changed nets, up to six times. Here it takes three passes: 74 nets, then 10, then 2, then 0. The passes add 112 diodes, on top of the 44 inserted after global routing.

Timing does not change: `clk` +4.51 ns, `mclk` +2.14 ns, hold +0.074 ns. DRC and LVS are clean.

## Smaller die

First, a sweep in a scratch copy of the flow ran floorplan, placement, CTS and global routing at three targets:

| Core utilization | Die (µm) | Result |
|---|---|---|
| 60% | 844 x 844 | Global routing clean |
| 65% | 812 x 812 | 1393 vertical congestion spots, all over the SRAM |
| 70% | 783 x 783 | Detailed placement fails during CTS |

At 65%, the area above the SRAM is too small and logic spills into the channels around it. Every net from those cells to the logic above crosses the macro, where the vertical routing capacity is close to zero. Three variants at 65% did not route:

| Variant at 65% | Result |
|---|---|
| SRAM flipped (MX), port 0 facing the logic | 1556 congestion spots |
| Channels blocked for placement, 2 rows kept for the SRAM input buffers | Detailed placement fails: 26 cells, mostly SRAM buffers |
| Aspect ratio 0.8 (906 x 729 µm) | 137 congestion spots |
| Aspect ratio 0.7 (967 x 683 µm) | 1098 congestion spots |

Decision: 60%.

The die shrinks from 923 x 923 to 844 x 844 µm, 16% less area. Utilization is 64%. Global routing has no congestion. Setup still closes: `clk` 65.3 MHz, `mclk` 124.5 MHz. Hold is +0.069 ns. Power is 16.7 mW. DRC and LVS are clean.

The antenna loop stops at its limit of six passes with 2 nets left (86, 13, 7, 4, 4, 3, 2). Both are met1 side-area checks, at 488 and 455 against 400. On that database, five more diode passes reach 0. A 10% `-ratio_margin` oscillates between 1 and 2 nets, and `-jumper_only` leaves both.

Decision: allow up to 12 passes.

## Longer antenna loop

