# PCIe PHY on die

Spec: [spec_v7.md](../spec_v7.md). The x1 root port from `pcie-x1` talks to a PHY macro on the die instead of the TI XIO1100 on the board. The macro is a placeholder with the views a licensed PHY ships with; [hard_phy.md](../hard_phy.md) covers a real one in its place.

## Branch base

The branch starts from `pcie-x1`: the x1 root port, the layout with the PHY pads, three-corner signoff and the timed simulation of the routed netlist.

## PHY macro

A hard PHY comes as a LEF abstract, liberty for each corner, GDS, a simulation model and a netlist for LVS. `macros/pcie_phy.py` writes the same views for an 800 x 800 µm placeholder from one pin table:

| View | Contents |
|---|---|
| LEF | 87 PIPE pins on met2 along the edge that faces the core, the lane, reference clock and REXT on met2 along the edge that faces the pads, supplies as met4 stripes, routing below met5 blocked |
| Liberty | tt, ss and ff: PIPE inputs with 1.0 ns setup and 0.5 ns hold at PCLK, outputs 1.5 ns after it, scaled to the slow and fast corners like the SRAM |
| GDS | the outline and the pins with their labels |
| Verilog | a black box |
| SPICE | an empty subcircuit for LVS |

The PIPE is 32 bits at 62.5 MHz with PCLK as a PHY input: the PHY drives MaxPCLK, and the clock tree takes it to the MAC and back into the PHY's PCLK pin. One clock tree serves both sides of the PIPE.

The PDK's `sky130_ef_io__analog_pad` is a straight met5 connection without ESD, a copy of `analog_noesd_pad`. A SerDes brings its own low-capacitance ESD, so the lane, reference clock and REXT use it. `vccd_lvc_clamped3` and `vssd_lvc_clamped3` pads give the PHY's 1.8 V analog supply its own core-side pins, VCCD1 and VSSD1, the way Caravel feeds its user supplies.

Decision: PIPE 32-bit with PCLK as a PHY input, the lane on analog pads, AVDD and AVSS on clamped3 pads.

## PIPE on die

`pcie_pipe.v` shrinks to one register stage on `pclk`: the gearbox, the falling-edge capture and the forwarded `pipe_tx_clk` go. One RxStatus, RxValid and PhyStatus per clock stand for both 16-bit words of the LTSSM. The 51 TI-PIPE pads give way to 7 analog pads.

The test runs against two new models:

- `pcie_phy.v`, the macro: MaxPCLK and a 0.4 ns bit time from the reference clock, 8b/10b, a serializer, bits recovered from the line's edges, comma alignment, RxPolarity, the elastic buffer, and receiver detection that releases the transmit lines and reads the endpoint's termination through the pads.
- `pcie_lane.v`, the endpoint's side of the lane: 8b/10b and a transmitter on the endpoint's own clock, 250 ppm off.

The endpoint model is unchanged. Lane polarity is swapped on the wire and decode errors are invalid codes on the wire.

The RTL simulation passes with the lane running as 2.5 Gb/s bit streams through the analog pads. The data link layer is up at 2.67 ms, the firmware enumerates the device with ERROR at 0, and the benchmark runs in 13,214 cycles cold and 12,484 warm, as with the XIO1100.

Every fault case from the XIO1100 tests passes and ends with the same STATUS and ERROR words as there:

| Fault | STATUS, ERROR |
|---|---|
| Bad LCRC on the endpoint's third TLP, decode error, swapped lane polarity, endpoint clock 250 ppm slow | 00000033, 0 |
| Nak of the root's fifth TLP, Ack withheld for the sixth | 00000133, 0: one replay |
| Endpoint enters Recovery | 00010033, 0: one Recovery |
| MRd, MWr and a Message from the endpoint | 00000033, 00000100 |
| Hot Reset from CONTROL | 00010033, 0; back in L0 2.07 ms later |

Hot Reset failed at first, with the endpoint flagging an ordered set cut short, and the fault was in the new models. The endpoint's side of the lane decoded the last symbol of an EIOS while it flushed the line into electrical idle, and raised idle before that symbol's strobe; the endpoint lost the symbol, and the next COM landed inside an unfinished EIOS. Idle now follows the strobe. The search also turned up a race in the PHY model: it began serializing with one word queued, so its fifth symbol fell due on the clock edge that queued the next word. It now waits for two words, like a transmit FIFO.

Synthesis gives 960k µm² of cells besides the 640k µm² macro. The synthesized netlist passes the same test in gate-level simulation, with flops starting at 0 and at 1.

Decision: lay out the chip with the PHY macro.
