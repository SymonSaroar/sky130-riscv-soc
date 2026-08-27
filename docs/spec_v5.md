# SoC specification v5

## Target

| Item | Value |
|---|---|
| Process | SKY130A |
| Standard cells | sky130_fd_sc_hd |
| Timing corner | tt_025C_1v80 |
| Clocks | `clk` 100 MHz (10 ns) for the system, `mclk` 100 MHz (10 ns) for the SDRAM controller, `pclk` 62.5 MHz (16 ns) from the PCIe PHY |
| Form | Hard macro, no pad ring |

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
| GPIO | `gpio.v` | 16 pins, separate in/out/output-enable |
| SPI | `spi.v` | Master, mode 0, SCLK = clk/2 |
| Timer | `timer.v` | 32-bit mtime/mtimecmp |
| Interrupt controller | `intc.v` | Level sources, enable mask, drives machine external interrupt |
| SDRAM port | `sdram.v`, `sdram_ctrl.v`, `async_fifo.v` | AXI4-Lite slave on `clk`, SDR SDRAM controller on `mclk`, async FIFOs between |
| PCIe port | `pcie.v`, `pcie_mac.v` | AXI4-Lite slave on `clk`, Gen1 x4 link and transaction layers on `pclk`, PIPE to an external PHY |

## Memory map

| Base | Size | Target |
|---|---|---|
| `0x0000_0000` | 2 KB | SRAM |
| `0x1000_0000` | 4 KB | UART |
| `0x1000_1000` | 4 KB | GPIO |
| `0x1000_2000` | 4 KB | SPI |
| `0x1000_3000` | 4 KB | Timer |
| `0x1000_4000` | 4 KB | Interrupt controller |
| `0x1000_5000` | 4 KB | PCIe status |
| `0x4000_0000` | 256 MB | PCIe memory space |
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
| PCIe | 0x0 | STATUS: bit 0 link up, bits 3:1 LTSSM state, bits 11:4 replays |

## CPU

- Reset vector `0x0`.
- Fetch reads SRAM port 1 for addresses below `0x8000_0000` and the instruction cache above it, into an instruction register. RR reads the register file, with forwarding from EX. Branches and jumps resolve in EX. A taken branch or jump costs two cycles.
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
| Refresh | Every 750 cycles (7.5 us) |
| Power-up | 100 us wait, precharge all, 2 auto refresh, mode register set |
| Clock crossing | Command and response async FIFOs, 4 entries, Gray-coded pointers |

## PCIe

| Item | Value |
|---|---|
| Link | Gen1 x4, root port, external PHY over 32-bit PIPE at 62.5 MHz |
| Requests | CPU loads and stores in `0x4000_0000` to `0x4FFF_FFFF` become MRd32 and MWr32 of one DW, tag 0, requester 0 |
| Completion | A store completes when the TLP is acknowledged; a load when the CplD arrives |
| Data link | Sequence numbers, LCRC, Ack/Nak, one-TLP retry buffer, replay after 2048 clocks, InitFC with infinite credits |
| Physical | Reduced LTSSM, TS1/TS2, SKP every 320 clocks, byte striping, packets aligned to 16-symbol blocks, scrambling disabled |

Scope and the reasons for an off-chip PHY are in [pcie_feasibility.md](pcie_feasibility.md).

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
| `gpio_in[15:0]`, `gpio_out[15:0]`, `gpio_oe[15:0]` | in, out, out | `gpio_in` synchronized |
| `spi_cs_n`, `spi_sclk`, `spi_mosi`, `spi_miso` | out, out, out, in | Boot flash and general SPI |
| `mclk` | in | 100 MHz |
| `sdram_clk` | out | Forwarded `mclk` |
| `sdram_cke`, `sdram_cs_n`, `sdram_ras_n`, `sdram_cas_n`, `sdram_we_n` | out | Command |
| `sdram_ba[1:0]`, `sdram_a[12:0]`, `sdram_dqm[1:0]` | out | Bank, address, byte mask |
| `sdram_dq_in[15:0]`, `sdram_dq_out[15:0]`, `sdram_dq_oe` | in, out, out | Data, split for an external I/O cell |
| `pclk`, `pipe_reset_n` | in, out | PIPE clock from the PHY, PHY reset |
| `pipe_tx_data[127:0]`, `pipe_tx_datak[15:0]`, `pipe_tx_elecidle`, `pipe_tx_detect_rx`, `pipe_power_down[1:0]` | out | PIPE transmit and control |
| `pipe_rx_data[127:0]`, `pipe_rx_datak[15:0]`, `pipe_rx_elecidle[3:0]`, `pipe_rx_status[11:0]`, `pipe_phy_status` | in | PIPE receive and status |

## Verification

- `make sim` boots from a flash model, runs the program from SDRAM through the instruction cache, and checks 52 RV32IM cases, the timer and UART interrupts, a SPI flash read, SDRAM word, halfword and byte accesses in four rows across three banks, the PCIe link up and memory writes and reads through a PCIe endpoint model, and an 8x8 matrix multiply against shift-and-add products.
- The SDRAM model flags protocol errors: access to a closed bank, tRCD, refresh with an open bank, refresh interval, commands before the mode register is set.
- `make lint` runs Verilator lint.
