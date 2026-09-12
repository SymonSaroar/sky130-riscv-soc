# SoC specification v8

## Target

| Item | Value |
|---|---|
| Process | SKY130A |
| Standard cells | sky130_fd_sc_hd |
| I/O cells | sky130_ef_io |
| Clocks | `clk` 100 MHz (10 ns) for the system and `mclk` 100 MHz (10 ns) for the SDRAM controller |
| Form | 2.12 x 2.12 mm chip: pad ring of 64 signal pads and 18 supply pads, seal ring |
| Supplies | VCCD 1.8 V core, VDDIO 3.3 V pads, VDDA 3.3 V |

## Blocks

| Block | RTL | Notes |
|---|---|---|
| CPU | `rv32i.v` | RV32IM + Zicsr, 5 stages (IF, ID, RR, EX, WB), machine mode only |
| Instruction cache | `icache.v` | SDRAM code. Direct-mapped, 64 lines of 32 bytes, data in a second `sky130_sram_2kbyte_1rw1r_32x512_8` |
| Boot loader | `boot.v` | Copies 2 KB from SPI flash to SRAM, then releases the CPU |
| Interconnect | `axil_ic.v` | AXI4-Lite, 2 masters, 3 slaves, one transaction at a time. Master 1 is the boot loader (writes) and the instruction cache (reads) |
| SRAM | `sram_axil.v` | `sky130_sram_2kbyte_1rw1r_32x512_8`. Port 0 on AXI, port 1 for instruction fetch |
| APB bridge | `axil2apb.v` | AXI4-Lite to APB, five zero-wait slaves |
| UART | `uart.v` | 8N1, programmable divider |
| GPIO | `gpio.v` | 16 bidirectional pins with output enables |
| SPI | `spi.v` | Master, mode 0, SCLK = clk/2, MISO sampled on the falling SCLK edge |
| Timer | `timer.v` | 32-bit mtime/mtimecmp |
| Interrupt controller | `intc.v` | Level sources, enable mask, drives machine external interrupt |
| SDRAM port | `sdram.v`, `sdram_ctrl.v`, `async_fifo.v` | AXI4-Lite slave on `clk`, SDR SDRAM controller on `mclk`, async FIFOs between |
| Pads | `chip_top.v` | `sky130_ef_io__gpiov2_pad_wrapped`: inputs in mode 001, outputs and bidirectional pins in mode 110, fast slew, CMOS input levels |

## Memory map

| Base | Size | Target |
|---|---|---|
| `0x0000_0000` | 2 KB | SRAM |
| `0x1000_0000` | 4 KB | UART |
| `0x1000_1000` | 4 KB | GPIO |
| `0x1000_2000` | 4 KB | SPI |
| `0x1000_3000` | 4 KB | Timer |
| `0x1000_4000` | 4 KB | Interrupt controller |
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

## Pad ring

Corners and supply pads are `sky130_ef_io` cells; bus slices fill the gaps and one slice per side ties VCCHIB to VCCD and VSWITCH to VDDIO. The pad cells' high-voltage enables come from their own tie outputs.

The SkyWater seal ring, from the PDK's generator, takes the outer 6 µm of the die. The pad ring starts 20 µm in.

| Side | Pads, in coordinate order |
|---|---|
| South | vssio, `sdram_a[0:2]`, vccd, `sdram_a[3:5]`, vdda, `sdram_a[6:8]`, vssa, `sdram_a[9:11]`, vssd, `sdram_a[12]`, `sdram_ba[0:1]`, vddio |
| East | `sdram_dq[0:3]`, vddio, `sdram_dq[4:7]`, vccd, `sdram_dq[8:11]`, vssio, `sdram_dq[12:15]`, vssd |
| North | `spi_cs_n`, `spi_sclk`, `spi_mosi`, `spi_miso`, vssd, `uart_tx`, `uart_rx`, `rst_n`, `clk`, vddio, `mclk`, `sdram_clk`, `sdram_cke`, `sdram_cs_n`, vccd, `sdram_ras_n`, `sdram_cas_n`, `sdram_we_n`, vssio, `sdram_dqm[0:1]` |
| West | vssio, `gpio[15:12]`, vccd, `gpio[11:8]`, vddio, `gpio[7:4]`, vssd, `gpio[3:0]` |

## I/O timing

| Interface | Budget |
|---|---|
| Board | 1 ns input edges, 5 pF on every output |
| SDRAM | MT48LC16M16A2-75: tIS 1.5 ns, tIH 0.8 ns, tAC 5.4 ns, tOH 2.7 ns, 1 ns board round trip |
| SPI flash | 2 ns setup, 3 ns hold, 7 ns clock to output, 0.5 ns of board each way |
| UART, GPIO, reset | Asynchronous |

## Signoff

| Corner | Cells | Pads | SRAM | Interconnect | Checks | Clocks |
|---|---|---|---|---|---|---|
| tt | tt_025C_1v80 | tt_tt_025C_1v80_3v30 | TT liberty | nominal | setup, hold, slew, load | 100 MHz |
| ss | ss_100C_1v60 | ss_ss_100C_1v60_3v00 | TT liberty, delays and setup x2.1 | max | setup, hold, slew, load | `clk` 50 MHz, `mclk` 62.5 MHz |
| ff | ff_n40C_1v95 | ff_ff_n40C_1v95_5v50 | TT liberty, delays x0.64 | min | setup, hold | 100 MHz |

The SRAM factors are the `dfxtp_2` clock-to-Q ratios between the corners. At the slow corner the clock-domain crossings are bounded by 16 ns. IR drop is sourced at the straps from the supply pads. Metal fill on the sky130 fill layers covers met1 to met5 outside the seal ring, the I/O cells and the SRAMs, and the layout passes the PDK's pattern density check.

## Verification

- `make sim` simulates the chip with the pad models: it boots from a flash model, runs the program from SDRAM through the instruction cache, and checks 52 RV32IM cases, the timer and UART interrupts, a SPI flash read, SDRAM word, halfword and byte accesses in four rows across three banks, and an 8x8 matrix multiply against shift-and-add products.
- The SDRAM model flags protocol errors: access to a closed bank, tRCD, refresh with an open bank, refresh interval, commands before the mode register is set.
- `make gls` runs the same test on the synthesized netlist, once with every flop starting at 0 and once at 1.
- `make lint` runs Verilator lint.
