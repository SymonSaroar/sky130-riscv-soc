# PCIe adapter

Spec: [spec_v4.md](../spec_v4.md). The SoC gains a PCIe Gen1 x4 root port. The link and transaction layers are on chip, and an external PHY handles the serial side over a 32-bit PIPE interface at 62.5 MHz ([pcie_feasibility.md](../pcie_feasibility.md)). CPU loads and stores in `0x4000_0000` to `0x4FFF_FFFF` become one-DW memory reads and writes. The macro goes from 113 to 424 pins.

The testbench connects the SoC to a second copy of the link layer in endpoint mode, through two PIPE PHY models, with 1 KB of memory behind it. The firmware waits for the link, writes eight words, reads them back and stores a byte. RTL simulation passes with the link in L0 and no replays.

Three mutations check that the test can fail. A flipped LCRC bit hangs the firmware, and rotated receive lanes stop link training. A wrong Ack sequence number passed at first, with 18 replays: the endpoint took each replayed TLP as a duplicate and acknowledged it with the right number. The firmware now also fails on any replay.

| Change | Setup WNS clk / mclk / pclk (ns) | Hold WNS (ns) | Gate-level sim | DRC / LVS |
|---|---|---|---|---|
| PCIe port, `pclk` at 16 ns | +1.43 / +2.39 / +4.54 | +0.078 | hangs | clean |

## Spec v4

Synthesis grows from 23,012 cells (809k µm²) to 27,724 cells (873k µm²), and flops from 3,472 to 5,021. The die is 1413 x 1413 µm at 45% core utilization.

The first detailed routing took 51 passes, about 40 of them at a single violation. It left 306 nets with antenna violations. The diode passes brought them to 34, 12 and 2, and the antenna buffers cleared the last two. The last routing pass stopped at its iteration limit with one met1 short that Magic, KLayout and LVS do not see.

Timing closes at signoff: `clk` +1.43 ns (73.7 MHz), `mclk` +2.39 ns (131 MHz), `pclk` +4.54 ns (87.3 MHz). Hold is +0.078 ns. Power is 45.7 mW and IR drop 5.02 mV. DRC and LVS are clean. No pin exceeds its capacitance limit, `u_sram.mem/dout1[10]` included.

![layout](../../reports/26-pcie-x4/layout.png)

Gate-level simulation hangs after the third PCIe write. The replay timer `replay_t` has no reset, and the transmitter clears it before first use. In the netlist the clear of bit 0 goes through an `o21ba` cell that computes `(Q | inc) & !(Q & (clr | inc))`. With `Q` unknown and the clear active, that is `X & !X`, which simulates as X. The X climbs the counter into `rb_send`, and the transmitter stops.

Hold repair after CTS pads the PIPE inputs. 1,079 of the 1,508 hold buffers sit on chains that start at PIPE receive pins, up to 12 in a row. The repair worked from a 2.27 ns `pclk` tree in the CTS estimate. At signoff the tree is 1.39 to 1.57 ns, and the padded `pipe_rx_datak[13]` has 3.3 ns more hold slack than it needs. The worst `pclk` setup path runs through those 12 buffers.

A candidate with the PIPE inputs registered on the rising edge ran through CTS. The input paths cleared, and hold repair added 2,976 buffers. The worst `pclk` path moved inside the link, to the check of a received TLP: in one cycle it selects a byte by counter, folds it into the CRC, compares the LCRC at a position chosen by the TLP length, checks END and the sequence number, and increments `rx_seq` (-0.40 ns at CTS).

Decision: capture the PIPE inputs on the falling edge of `pclk` and again on the rising edge, compare the LCRC from a register with a two-way length select, and reset the replay timer.
