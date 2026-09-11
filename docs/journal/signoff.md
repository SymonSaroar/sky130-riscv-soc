# Signoff

Spec: [spec_v8.md](../spec_v8.md). Signoff covers three corners instead of one. Setup is checked at the slow corner (ss_100C_1v60 with maximum interconnect RC) and hold at the fast corner (ff_n40C_1v95 with minimum RC), on top of the typical corner. The pads have liberty files for both corners. The SRAM has only a TT liberty, so the slow and fast corners use copies scaled by the clock-to-Q ratio of a standard-cell flop: delays and setup constraints x2.1 at the slow corner, delays x0.64 at the fast one. Each corner runs in its own STA session, because in one multi-corner session the clocks forwarded through the pads keep one latency for all corners. IR drop is now sourced where the straps from the supply pads meet the ring.

| Change | Setup WNS clk / mclk, tt (ns) | Setup WNS clk / mclk, ss (ns) | Hold WNS tt / ff (ns) | DRC / LVS |
|---|---|---|---|---|
| Three corners on the pad-ring layout | +0.86 / +0.50 | -8.32 / -2.87 | +0.022 / -0.086 | clean |

## Three corners

Extraction, STA and IR analysis run again on the pad-ring layout; synthesis, place and route, DRC and LVS are unchanged.

The typical corner matches the pad-ring signoff. The slow corner fails setup on 2,830 endpoints:

| Path | Slack at ss (ns) |
|---|---|
| Inside the core, `clk` | -8.32 (54.6 MHz) |
| Inside the SDRAM controller, `mclk` | -2.87 (77.7 MHz) |
| SDRAM write data to `sdram_dq[15]` | -1.39 |
| SPI MOSI and CS | +6.61 |

Hold at the fast corner fails on 22 endpoints, by up to 0.086 ns, all between flops inside the core; the SDRAM and SPI pins keep more than 4 ns. At the slow corner the net that breaks its limits at tt reaches 4.28 ns of slew against 1.49 ns, and two more nets go over.

IR drop from the pads is 17.3 mV on VPWR and 16.3 mV on VGND, against 2 mV when every met5 node was a source.

Decision: specify the slow corner at 50 MHz on both clocks and size the SDRAM refresh interval for 50 MHz, repair hold at the typical corner with 0.2 ns of margin, repair slew and load once more after timing repair, and fill the metal layers.
