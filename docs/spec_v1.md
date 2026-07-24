# SoC specification v1

## Target

| Item | Value |
|---|---|
| Process | SKY130A |
| Standard cells | sky130_fd_sc_hd |
| Timing corner | tt_025C_1v80 |
| Clock | 50 MHz (20 ns), single domain |
| Form | Hard macro, no pad ring |

## Blocks

| Block | RTL | Notes |
|---|---|---|
| CPU | `rv32i.v` | RV32I + Zicsr, 4 stages (IF, ID, EX, WB), machine mode only |
| Boot loader | `boot.v` | Copies 2 KB from SPI flash to SRAM, then releases the CPU |
| Interconnect | `axil_ic.v` | AXI4-Lite, 2 masters, 2 slaves, one transaction at a time |
| SRAM | `sram_axil.v` | `sky130_sram_2kbyte_1rw1r_32x512_8`. Port 0 on AXI, port 1 for instruction fetch |
| APB bridge | `axil2apb.v` | AXI4-Lite to APB, zero-wait slaves |
| UART | `uart.v` | 8N1, programmable divider |
| GPIO | `gpio.v` | 16 pins, separate in/out/output-enable |
| SPI | `spi.v` | Master, mode 0, SCLK = clk/2 |
| Timer | `timer.v` | 32-bit mtime/mtimecmp |
| Interrupt controller | `intc.v` | Level sources, enable mask, drives machine external interrupt |

## Memory map

| Base | Size | Target |
|---|---|---|
| `0x0000_0000` | 2 KB | SRAM |
| `0x1000_0000` | 4 KB | UART |
| `0x1000_1000` | 4 KB | GPIO |
| `0x1000_2000` | 4 KB | SPI |
| `0x1000_3000` | 4 KB | Timer |
| `0x1000_4000` | 4 KB | Interrupt controller |

## Registers

| Block | Offset | Register |
|---|---|---|
| UART | 0x0 | DATA: write sends, read returns the last byte and clears `rx_valid` |
| | 0x4 | STATUS: bit 0 `tx_busy`, bit 1 `rx_valid` |
| | 0x8 | DIV: clocks per bit, reset 434 (115200 baud) |
| GPIO | 0x0 / 0x4 / 0x8 | OUT / IN / OE |
| SPI | 0x0 | CS: bit 0 drives `spi_cs_n` |
| | 0x4 | DATA: write starts a byte, read returns the received byte |
| | 0x8 | STATUS: bit 0 busy |
| Timer | 0x0 / 0x4 | MTIME / MTIMECMP |
| INTC | 0x0 / 0x4 | PENDING (bit 0 UART rx, bit 1 SPI idle) / ENABLE |

## CPU

- Reset vector `0x0`.
- Fetch reads SRAM port 1 directly into an instruction register. Branches and jumps resolve in EX. A taken branch or jump costs one cycle.
- One load or store in flight. An instruction that reads a register still being loaded waits one cycle.
- CSRs: `mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`. `mret` supported.
- Interrupts: machine timer and machine external. No synchronous exceptions.
- `fence`, `ecall`, `ebreak` and `wfi` execute as no-ops.

## Boot

- Reset holds the CPU while the boot loader sends `0x03 00 00 00` and streams 2048 bytes into SRAM.
- The flash pins switch to the SPI peripheral when boot finishes.

## Pins

| Pin | Dir | Notes |
|---|---|---|
| `clk` | in | 50 MHz |
| `rst_n` | in | Synchronized internally |
| `uart_tx`, `uart_rx` | out, in | `uart_rx` synchronized |
| `gpio_in[15:0]`, `gpio_out[15:0]`, `gpio_oe[15:0]` | in, out, out | `gpio_in` synchronized |
| `spi_cs_n`, `spi_sclk`, `spi_mosi`, `spi_miso` | out, out, out, in | Boot flash and general SPI |

## Verification

- `make sim` boots firmware from a flash model and checks 36 RV32I cases, the timer and UART interrupts, and a SPI flash read.
- `make lint` runs Verilator lint.
