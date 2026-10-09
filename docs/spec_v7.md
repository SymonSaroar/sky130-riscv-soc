# SoC specification v7

## Target

| Item | Value |
|---|---|
| Process | SKY130A |
| Standard cells | sky130_fd_sc_hd |
| I/O cells | sky130_ef_io |
| Clocks | `clk` 100 MHz (10 ns) for the system, `mclk` 100 MHz (10 ns) for the SDRAM controller, `pclk` 62.5 MHz (16 ns) from the PCIe PHY's MaxPCLK |
| Form | Standalone die, 2.4 x 2.4 mm: pad ring of 64 digital signal pads, 7 analog pads for the PCIe lane and their supply pads, seal ring |
| Supplies | VCCD 1.8 V core, VDDIO 3.3 V pads, VDDA 3.3 V, AVDD 1.8 V for the PCIe PHY's analog circuits |
| PCIe PHY | `pcie_phy` hard macro, x1 Gen1, PIPE 32-bit at 62.5 MHz with PCLK as a PHY input. A placeholder with the views of a licensed PHY: LEF, liberty, GDS, black box and SPICE subcircuit |

## Blocks

| Block | RTL | Notes |
|---|---|---|
| CPU | `rv32i.v` | RV32IM + Zicsr, 5 stages (IF, ID, RR, EX, WB), machine mode only |
| Instruction cache | `icache.v` | SDRAM code. Direct-mapped, 64 lines of 32 bytes, data in a second `sky130_sram_2kbyte_1rw1r_32x512_8` |
| Boot loader | `boot.v` | Copies 2 KB from SPI flash to SRAM, then releases the CPU |
| Interconnect | `axil_ic.v` | AXI4-Lite, 2 masters, 4 slaves, one transaction at a time. Master 1 is the boot loader (writes) and the instruction cache (reads) |
| SRAM | `sram_axil.v` | `sky130_sram_2kbyte_1rw1r_32x512_8`. Port 0 on AXI, port 1 for instruction fetch |
| APB bridge | `axil2apb.v` | AXI4-Lite to APB, six zero-wait slaves |
| UART | `uart.v` | 8N1, programmable divider |
| GPIO | `gpio.v` | 16 bidirectional pins with output enables |
| SPI | `spi.v` | Master, mode 0, SCLK = clk/2, MISO sampled on the falling SCLK edge |
| Timer | `timer.v` | 32-bit mtime/mtimecmp |
| Interrupt controller | `intc.v` | Level sources, enable mask, drives machine external interrupt |
| SDRAM port | `sdram.v`, `sdram_ctrl.v`, `async_fifo.v` | AXI4-Lite slave on `clk`, SDR SDRAM controller on `mclk`, async FIFOs between |
| PCIe port | `pcie.v`, `pcie_pipe.v`, `pcie_ltssm.v`, `pcie_dll.v` | Root port. AXI4-Lite slave and APB registers on `clk`, PIPE registers, transaction, data link and logical physical layers on `pclk`, async FIFOs between `clk` and `pclk` |
| Pads | `chip_top.v` | `sky130_ef_io__gpiov2_pad_wrapped`: inputs in mode 001, outputs and bidirectional pins in mode 110, fast slew, CMOS levels on VDDIO. The PCIe lane, reference clock and calibration resistor on `sky130_ef_io__analog_pad` |
| PCIe PHY | `pcie_phy` | Hard macro between the PIPE registers and the analog pads |

## Memory map

| Base | Size | Target |
|---|---|---|
| `0x0000_0000` | 2 KB | SRAM |
| `0x1000_0000` | 4 KB | UART |
| `0x1000_1000` | 4 KB | GPIO |
| `0x1000_2000` | 4 KB | SPI |
| `0x1000_3000` | 4 KB | Timer |
| `0x1000_4000` | 4 KB | Interrupt controller |
| `0x1000_5000` | 4 KB | PCIe registers |
| `0x4000_0000` | 256 MB | PCIe memory space: MRd and MWr of one DW to the same address |
| `0x5000_0000` | 256 MB | PCIe configuration space, ECAM layout: bus addr[27:20], device addr[19:15], function addr[14:12], register addr[11:2] |
| `0x8000_0000` | 32 MB | SDRAM |

## Registers

| Block | Offset | Register |
|---|---|---|
| UART | 0x0 | DATA: write sends, read returns the last byte and clears `rx_valid` |
| | 0x4 | STATUS: bit 0 `tx_busy`, bit 1 `rx_valid` |
| | 0x8 | DIV: clocks per bit, reset 434. Firmware writes 868 (115200 baud at 100 MHz) |
| GPIO | 0x0 / 0x4 / 0x8 | OUT / IN / OE |
| SPI | 0x0 | CS: bit 0 drives `spi_cs_n` |
| | 0x4 | DATA: write starts a byte, read returns the received byte |
| | 0x8 | STATUS: bit 0 busy |
| Timer | 0x0 / 0x4 | MTIME / MTIMECMP |
| INTC | 0x0 / 0x4 | PENDING (bit 0 UART rx, bit 1 SPI idle) / ENABLE |
| PCIe | 0x0 | STATUS: bit 0 DL_Up, bit 1 LinkUp, bits 6:2 LTSSM state, bits 15:8 replays, bits 23:16 entries to Recovery (both counters saturate) |
| | 0x4 | CONTROL: bit 0 holds the PHY in reset (reset value 1), bit 1 directs Hot Reset, bit 2 directs Recovery |
| | 0x8 | ERROR, write 1 to clear: bit 0 completion timeout, bit 1 UR, bit 2 CA, bit 3 RRS, bit 4 bad TLP, bit 5 bad DLLP, bit 6 receiver error, bit 7 malformed TLP, bit 8 inbound request answered with UR or dropped |

## CPU

- Reset vector `0x0`.
- Fetch reads SRAM port 1 for addresses below `0x8000_0000` and the instruction cache above it, into an instruction register. Fetch does not wait for a cache hit: after a miss, the next fetch goes back to the address that missed. RR reads the register file, with forwarding from EX. Branches and jumps resolve in EX. A taken branch or jump costs two cycles.
- MUL, MULH, MULHSU and MULHU take 2 extra cycles. DIV, DIVU, REM and REMU take 32 extra cycles.
- One load or store in flight, driven on the bus from WB registers. An instruction that reads a register still being loaded waits in RR until the cycle after the response.
- CSRs: `mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`. `mret` supported.
- Interrupts: machine timer and machine external. No synchronous exceptions.
- `fence`, `ecall`, `ebreak` and `wfi` execute as no-ops.

## SDRAM

| Item | Value |
|---|---|
| Device | 16-bit SDR SDRAM, 4 banks x 8192 rows x 512 columns (MT48LC16M16A2 class) |
| Clock | `mclk`, forwarded to the device as `sdram_clk` |
| Access | One 32-bit word: ACTIVE, then READ or WRITE with auto-precharge, burst of 2 |
| Address | Row = addr[24:12], bank = addr[11:10], column = {addr[9:2], beat} |
| Mode | CAS latency 3, burst length 2, sequential |
| Timing (cycles) | tRCD 2, tRP 2, tRFC 7, tMRD 2, tWR 2 |
| Refresh | Every 480 cycles: 4.8 us at 100 MHz, 7.7 us at 62.5 MHz |
| Power-up | 100 us wait, precharge all, 2 auto refresh, mode register set |
| Pins | Driven from falling-edge registers of `mclk`; read data captured on the falling edge, a cycle and a half after the SDRAM clock edge |
| Clock crossing | Command and response async FIFOs, 4 entries, Gray-coded pointers |

## Instruction cache

| Item | Value |
|---|---|
| Cached range | `0x8000_0000` and up |
| Organization | Direct-mapped, 64 lines x 32 bytes = 2 KB |
| Tags | 14 bits (addr[24:11]) plus valid, in flops |
| Lookup | Same timing as the SRAM: address in one cycle, data and hit the next |
| Miss | 8 AXI4-Lite reads; the line becomes valid one cycle after the last word is written |

## Boot

- Reset holds the CPU while the boot loader sends `0x03 00 00 00` and streams 2048 bytes into SRAM.
- The flash pins switch to the SPI peripheral when boot finishes.
- The first-stage program in SRAM reads a length word at flash `0x800`, copies the program that follows into SDRAM at `0x8000_0000`, and jumps to it. That program keeps its zeroed data and stack in SRAM.

## PCIe port

Root port, x1, 2.5 GT/s. The PHY does 8b/10b, scrambling, the elastic buffer and receiver detection.

### PHY interface

| Item | Value |
|---|---|
| Mode | PIPE, 32 bits per PCLK, four symbols per clock, symbol 0 in bits 7:0. One RxStatus, RxValid and PhyStatus per clock, for all four symbols |
| PCLK | PCLK as a PHY input: the PHY drives MaxPCLK at 62.5 MHz from the 100 MHz reference clock, the clock tree takes it to the MAC and back into the PHY's PCLK pin |
| Receive | PHY outputs launched by PCLK, captured by `pclk` registers |
| Transmit | Driven from `pclk` registers, sampled by the PHY on PCLK |
| Reset | CONTROL bit 0 drives the PHY's Reset#. While it is low: TxDetectRx 0, TxElecIdle 1, TxCompliance 0, RxPolarity 0, PowerDown P1. The PHY is ready when it drops PhyStatus |
| Power states | P1 in Detect, P0 everywhere else. P0s is not used |
| Electrical idle | One EIOS (COM, IDL, IDL, IDL) before TxElecIdle is set |
| Compliance | TxCompliance with the word whose symbol 0 is the first K28.5 |

### PHY macro

| Item | Value |
|---|---|
| Size | 800 x 800 µm. Routing below met5 blocked except at the pins; the met5 grid crosses it |
| Pins | PIPE on met3 along the west edge, which faces the core, 5 µm apart. TXP, TXN, RXP, RXN, REFCLKP, REFCLKN and REXT on met3 along the east edge, which faces the pads, at the analog pads' 75 µm pitch; AVDD and AVSS as 40 µm met3 bars in the gaps next to the outer ones. VCCD and VSSD as met4 stripes every 100 µm |
| Timing | PIPE inputs: setup 1.0 ns and hold 0.5 ns at PCLK rising. PIPE outputs 1.5 ns after PCLK rising, 0.2 ns edges. Typical-corner values; delays scale x2.1 at the slow corner and x0.64 at the fast one, setup x2.1 at the slow corner |
| Power | 10 mW on VCCD in the liberty |
| Supplies | VCCD and VSSD from the core grid through the met5 stripes over the macro. AVDD and AVSS on met4 buses between the core ring and the PHY pads: met3 straps from the clamped3 pads' VCCD1 and VSSD1 pins onto the buses, and from the buses under the core ring onto the macro's bars |
| Placement | Against the east edge of the core, centred on its pads, so no rows lie between its pad-side pins and the core ring |
| Views | Generated from one pin table: LEF, liberty for three corners, GDS with the pins and the outline, Verilog black box, SPICE subcircuit |

### Logical physical layer

| Item | Value |
|---|---|
| LTSSM | Detect.Quiet, Detect.Active, Polling.Active, Polling.Compliance, Polling.Configuration, Configuration (Linkwidth.Start, Linkwidth.Accept, Lanenum.Wait, Lanenum.Accept, Complete, Idle) as a Downstream Port, L0, Recovery (RcvrLock, RcvrCfg, Idle), Hot Reset |
| Timeouts | Detect.Quiet 12 ms, Polling.Active 24 ms, Polling.Configuration 48 ms, Configuration.Linkwidth.Start 24 ms, other Configuration substates 2 ms, Recovery.RcvrLock 24 ms, Recovery.RcvrCfg 48 ms, Recovery.Idle 2 ms, Hot Reset 2 ms. A parameter divides them in RTL simulation |
| TS1/TS2 | Link 0, Lane 0, N_FTS 255, Data Rate Identifier 02h (2.5 GT/s only), Training Control 00h except the Hot Reset bit in Hot Reset |
| Polarity | RxPolarity set when Polling sees D21.5 in TS1 or D26.5 in TS2 symbols 6 to 15 |
| Compliance | K28.5, D21.5, K28.5, D10.2 repeating, TxCompliance with the first K28.5. Exit on electrical idle exit |
| Symbol lock | The receive stream is realigned on every COM: SKP add or remove in the PHY can move it by one symbol |
| SKP | COM plus three SKP sent every 1280 symbol times, held to the next packet boundary. Received SKP ordered sets of one to five SKP are dropped |
| Framing | STP and SDP at any symbol position, packets back to back. Logical idle is data 00h |
| Leaving L0 | Recovery on a received TS1 or TS2, a received EIOS, no SKP for 128 us, four replays without progress, or CONTROL bit 2 |
| Errors | RxStatus decode, disparity and elastic buffer errors are receiver errors: the TLP or DLLP in progress is dropped and a Nak is scheduled |

### Data link layer

| Item | Value |
|---|---|
| States | DL_Inactive, DL_Init (FC_INIT1, FC_INIT2), DL_Active. Data Link Feature DLLPs are ignored |
| Credits advertised | PH and PD infinite, NPH 4, NPD 4, CplH and CplD infinite. UpdateFC-NP when credits are freed and every 30 us in L0 |
| Credits tracked | The device's PH, PD, NPH and NPD limits from InitFC and UpdateFC, 8-bit header and 12-bit data counters. A TLP waits until it fits |
| Retry buffer | Four TLPs |
| Replay | REPLAY_TIMER 28,000 symbol times. REPLAY_NUM counts replays; the fourth without progress sends the LTSSM to Recovery |
| Ack | Scheduled within 128 symbol times of a TLP reaching the transaction layer. Nak on a bad LCRC, a receiver error or a sequence gap; Ack for a duplicate |
| Priority | Current packet, Nak, Ack, UpdateFC, replay, new TLPs, InitFC |
| CRC | LCRC 04C11DB7h and DLLP CRC 100Bh, seed all ones, bit 0 first, complemented, bytes reflected into the field as tables 3-6 and 3-7 of the base specification |
| Receive size | Payload up to 128 bytes (Rx_MPS_Limit), header up to 4 DW, optional digest. The LCRC is computed four bytes per `pclk` |

### Transaction layer

| Item | Value |
|---|---|
| Requests | MRd32 and MWr32 of one DW with the store's byte enables, CfgRd0 and CfgWr0 to bus 1, device 0. Requester ID 0000h, one request in flight, tag increments per request |
| Other config targets | Completed inside the port with UR, no TLP |
| Completions | Matched by tag. SC returns the data; UR, CA and RRS return FFFF_FFFFh and set ERROR. RRS is retried by firmware |
| Completion timeout | 10 ms, then FFFF_FFFFh and ERROR bit 0 |
| Inbound requests | Posted (MWr, Msg, MsgD) dropped after the data link layer accepts them. Non-posted answered with Cpl, status UR |
| Inbound completions | Without a matching request: dropped |
| Malformed | Length and payload mismatch, payload over 128 bytes, or an unknown Fmt and Type: dropped, ERROR bit 7 |
| DL_Down | The request in flight completes with FFFF_FFFFh and ERROR bit 1 |

Not implemented: L0s, L1, L2, Loopback, Disabled, speed change, ECRC generation and checking, AER, MSI and INTx delivery to the CPU, a PCI bridge configuration header for the port itself.

## Pins

| Pin | Dir | Notes |
|---|---|---|
| `clk` | in | 100 MHz |
| `rst_n` | in | Synchronized internally |
| `uart_tx`, `uart_rx` | out, in | `uart_rx` synchronized |
| `gpio[15:0]` | inout | Input synchronized |
| `spi_cs_n`, `spi_sclk`, `spi_mosi`, `spi_miso` | out, out, out, in | Boot flash and general SPI |
| `mclk` | in | 100 MHz |
| `sdram_clk` | out | Forwarded `mclk` |
| `sdram_cke`, `sdram_cs_n`, `sdram_ras_n`, `sdram_cas_n`, `sdram_we_n` | out | Command |
| `sdram_ba[1:0]`, `sdram_a[12:0]`, `sdram_dqm[1:0]` | out | Bank, address, byte mask |
| `sdram_dq[15:0]` | inout | Data |
| `pcie_txp`, `pcie_txn` | analog | PCIe lane, transmit |
| `pcie_rxp`, `pcie_rxn` | analog | PCIe lane, receive |
| `pcie_refclk_p`, `pcie_refclk_n` | analog | 100 MHz HCSL reference clock |
| `pcie_rext` | analog | Calibration resistor to ground |

## Pad ring

The ring follows SkyWater's `sky130_fd_io` user guide. Corners and supply pads are `sky130_ef_io` cells.

- `gpiov2` pads abut, every other one mirrored.
- Supply pads come in pairs: `vddio` with `vssio` and `vdda` with `vssa` back to back, the second one mirrored; `vssd` and `vccd` on their compliant sides, with a bus slice of at least 12 µm on each outer side.
- One slice per side ties VCCHIB to VCCD and VSWITCH to VDDIO. Bus slices fill the rest of each side.
- The pad cells' high-voltage enables come from their own tie outputs.
- The PCIe lane, reference clock and REXT pads sit together in the middle of the east side, next to the PHY macro, between two AVSS/AVDD pairs (`vssd_lvc_clamped3` and `vccd_lvc_clamped3`, whose VCCD1 and VSSD1 pins feed the macro). Each pair keeps a 12 µm bus slice on its outer sides, like VSSD/VCCD.

The SkyWater seal ring, from the PDK's generator, takes the outer 6 µm of the die. The pad ring starts 20 µm in.

`make pads` lists every pad opening with its pin or supply and its centre, numbered counter-clockwise from the south-west corner.

## I/O timing

| Interface | Budget |
|---|---|
| Board | 1 ns input edges, 5 pF on every output |
| SDRAM | MT48LC16M16A2-75: tIS 1.5 ns, tIH 0.8 ns, tAC 5.4 ns, tOH 2.7 ns, 1 ns board round trip |
| SPI flash | 2 ns setup, 3 ns hold, 7 ns clock to output, 0.5 ns of board each way |
| PIPE | From the PHY macro's liberty, on chip |
| UART, GPIO, reset | Asynchronous |

## Signoff

| Corner | Cells | Pads | SRAM | Interconnect | Checks | Clocks |
|---|---|---|---|---|---|---|
| tt | tt_025C_1v80 | tt_tt_025C_1v80_3v30 | TT liberty | nominal | setup, hold, slew, load | `clk`, `mclk` 100 MHz, `pclk` 62.5 MHz |
| ss | ss_100C_1v60 | ss_ss_100C_1v60_3v00 | TT liberty, delays and setup x2.1 | max | setup, hold, slew, load | `clk` 50 MHz, `mclk` 62.5 MHz, `pclk` 62.5 MHz |
| ff | ff_n40C_1v95 | ff_ff_n40C_1v95_5v50 | TT liberty, delays x0.64 | min | setup, hold | `clk`, `mclk` 100 MHz, `pclk` 62.5 MHz |

The SRAM and PHY macro factors are the `dfxtp_2` clock-to-Q ratios between the corners. At the slow corner the crossings between `clk` and `mclk` are bounded by 16 ns, and those between `clk` and `pclk` by 16 ns. Hold is repaired at the typical corner with 0.3 ns of margin. IR drop is sourced at the straps from the supply pads.

| Check | Requirement |
|---|---|
| DRC | The PDK's KLayout deck (FEOL, BEOL, off-grid, seal ring) on the whole GDS, nothing waived |
| Fill | Every layer from the PDK fill generator, clear of the seal ring, the I/O cells, and the SRAMs below met4; the PDK's KLayout density deck passes |
| Electromigration | Every power-grid segment and via within the tech LEF's average-current limits at 90 °C |
| Equivalence | The routed netlist proven equivalent to the synthesized one, with flops, SRAMs and pads as matched cut points |
| LVS | Netgen on the Magic extraction, the PHY macro as a black box |

## Verification

- `make sim` simulates the chip with the pad models: it boots from a flash model, runs the program from SDRAM through the instruction cache, and checks 52 RV32IM cases, the timer and UART interrupts, a SPI flash read, SDRAM word, halfword and byte accesses in four rows across three banks, an 8x8 matrix multiply against shift-and-add products, and the PCIe link.
- The SDRAM model flags protocol errors: access to a closed bank, tRCD, refresh with an open bank, refresh interval, commands before the mode register is set.
- The PCIe test runs against models written from the base specification and PIPE, separate from the RTL:
  - `pcie_phy.v`: the PHY macro. PIPE timing checks, reset and PhyStatus handshakes, power states, receiver detection on the transmit lines, 8b/10b, a 2.5 Gb/s serial lane, clock recovery, comma alignment, RxPolarity, an elastic buffer that adds and removes SKP symbols, electrical idle.
  - `pcie_lane.v`: the endpoint's side of the lane: 8b/10b, a 2.5 Gb/s transmitter 250 ppm off the reference clock, clock recovery, receiver termination.
  - `pcie_dev.v`: an endpoint with its own LTSSM, data link layer, finite credits with UpdateFC, a Type 0 header with a 4 KB memory BAR, and RRS for its first configuration reads. It flags protocol violations by the root, including missing SKP ordered sets and UpdateFC-NP.
- The firmware waits for DL_Up, enumerates the device with RRS retry, sizes and assigns BAR0, enables memory space, writes and reads words and a byte, and checks the ERROR and STATUS registers. With `gpio[9]` pulled high it then directs a Hot Reset and enumerates again.
- Plusargs inject faults, with `gpio[8]` pulled high so the firmware reports the link errors instead of failing on them: a bad LCRC, a Nak, a withheld Ack, a Recovery entered by the device, a decode error, requests from the device, a swapped lane polarity, and the clock offset the other way.
- `make gls` runs the same test on the synthesized netlist, once with every flop starting at 0 and once at 1.
- `make gls_sdf` runs it on the routed netlist with the delays from signoff STA, pads included; `CORNER=ss` and `CORNER=ff` run the slow and fast corners. The SRAM model drives its read data between the smallest and largest clock-to-dout delay in its liberty.
- `make lint` runs Verilator lint.
