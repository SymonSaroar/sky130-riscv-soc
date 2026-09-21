# PCIe x1 port

Spec: [spec_v6.md](../spec_v6.md). The x4 port becomes an x1 root port for a real PHY, the TI XIO1100, inside the standalone chip from `main`.

## Branch base

The branch starts from the SoC with the x4 port and takes the chip work from `main`: the pad ring, the seal ring, three-corner signoff, fill, equivalence and electromigration checks. The x4 PIPE has 311 pins, more than a pad ring can carry, so `chip_top` passes it to the chip edge without pads.

RTL simulation of the chip with the pad models passes, PCIe included. Synthesis gives 887k µm² and 5,706 flops.

## PHY interface voltage

The XIO1100's TI-PIPE pins run at 1.5 or 1.8 V, and its inputs take no more than its own I/O supply. The PDK has `gpiov2` libraries with VDDIO at 3.3 V and at 1.65 to 1.95 V:

| Pad library | Output into 5 pF, rise / fall (ns) | Output edges (ns) | 1.8 V input, 1 ns edge (ns) |
|---|---|---|---|
| tt, VDDIO 3.3 V | 3.97 / 4.10 | 1.41 / 1.21 | 1.87 / 1.65 |
| ss, VDDIO 3.0 V | 6.07 / 6.20 | 2.35 / 1.84 | 2.96 / 2.60 |
| ff, VDDIO 5.5 V | 2.37 / 2.31 | 0.89 / 0.75 | 1.33 / 1.16 |
| ss, VDDIO 1.65 V | 13.86 / 16.17 | 6.49 / 5.00 | 2.96 / 2.58 |
| ff core, ss I/O, VDDIO 1.95 V | 8.61 / 9.95 | 3.63 / 3.10 | 1.52 / 1.44 |

At 1.65 to 1.95 V the outputs take 9 to 16 ns, more than the 8 ns clock period. In the 1.8 V input mode (`IB_MODE_SEL` 1) the input buffer runs from VCCHIB and reads 1.8 V levels with the ring at 3.3 V.

Decision: keep the ring at 3.3 V, read the PHY's outputs in the 1.8 V input mode, and drive its inputs through 3.3 V to 1.8 V translators on the board.

## Interface timing on paper

Transmit data leaves falling-edge registers and `pipe_tx_clk` is the clock forwarded through the same kind of pad, so the pad delay cancels. Receive data is captured on the falling edge of `pipe_rx_clk` after its own input pad. The budget assumes 0.3, 0.5 and 0.2 ns of clock skew between the PHY pin registers, 1.2, 2.2 and 0.8 ns of clock insertion from the pad, 0.5 ns of translator skew and 0.1 ns of trace mismatch.

| Corner | TX setup (ns) | TX hold (ns) | RX setup (ns) | RX hold (ns) |
|---|---|---|---|---|
| tt | 1.31 | 3.34 | 2.73 | 3.35 |
| ss | 0.78 | 3.44 | 3.59 | 2.35 |
| ff | 1.67 | 3.26 | 2.37 | 3.75 |

The pins close at every corner. The link runs on `pclk`, half of `pipe_rx_clk`, and has to close 62.5 MHz at the slow corner as well, since a PCIe clock cannot slow down. The x4 link reached 93.6 MHz at the typical corner, and on `main` the CPU runs at 109.8 MHz typical and 53.8 MHz slow.

The 51 PHY pins bring the ring to 115 signal pads. With the supply pairs that is about 35 pads a side and a die of about 3.3 mm.

Decision: 16-bit words at 125 MHz paired into 32 bits on `pclk`, a link pipelined for 62.5 MHz at the slow corner, and a pad ring of about 3.3 mm.
