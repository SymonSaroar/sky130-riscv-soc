# Place and route cleanup

Starting point: the external memory design. Timing and hold close, DRC and LVS are clean, 74 nets have antenna violations, and the die is 923 x 923 µm with standard cells filling about a fifth of it.

| Change | Die (µm) | Antenna nets | Setup WNS clk / mclk (ns) | Hold WNS (ns) | DRC / LVS |
|---|---|---|---|---|---|
| Antenna repair after detailed routing | 923 x 923 | 0 | +4.51 / +2.14 | +0.074 | clean |

## Antenna repair after detailed routing

The 74 violations are all side-area ratio checks: met2 41, met1 29, met3 19, met4 2. The median net is 1.27 times over the limit and the worst 8.4 times. The flow repairs antennas on the global routes, and detailed routing then lays different wires.

After detailed routing, the flow now checks antennas, inserts diodes on the violating nets, and reroutes only the changed nets, up to six times. Here it takes three passes: 74 nets, then 10, then 2, then 0. The passes add 112 diodes, on top of the 44 inserted after global routing.

Timing does not change: `clk` +4.51 ns, `mclk` +2.14 ns, hold +0.074 ns. DRC and LVS are clean.

## Smaller die
