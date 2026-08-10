# Performance push

Spec: [spec_v3.md](../spec_v3.md). The CPU gains the M extension, code runs from SDRAM through a 2 KB instruction cache in a second SRAM macro, and the system clock target moves from 50 to 66.7 MHz (15 ns).

The firmware boots in two stages. A 292-byte loader in SRAM copies the program from SPI flash into SDRAM and jumps to it. That program runs 50 RV32IM checks (14 of them for the M extension, including divide by zero and -2^31 / -1), the interrupt, SPI and SDRAM tests, and an 8x8 matrix multiply with divides whose products are checked against shift-and-add. RTL and gate-level simulation pass with 0 SDRAM protocol errors. Marking a cache line valid when its refill starts makes the test hang at `0x80000000`.

The benchmark takes 10,937 cycles cold and 10,347 warm.

| Change | Setup WNS clk / mclk (ns) | Failing endpoints | Hold WNS (ns) | DRC / LVS |
|---|---|---|---|---|
| M extension, instruction cache, 15 ns clock | -3.08 / +1.81 | 928 | +0.076 | clean |
| Two-cycle multiplier | routing stopped | | | |
| No buffering in the timing repair after global routing | | | | |

## Spec v3

Synthesis grows from about 410k to 805k µm²: the second SRAM is 285k, and standard cells go from about 121k to 235k µm². The cache SRAM sits in the upper-left corner, mirrored, so that its fetch port faces down toward the core. The die is 1178 x 1178 µm at 64% utilization.

![layout](../../reports/20-rv32m-icache/layout.png)

| Check | Result |
|---|---|
| Setup `clk` | -3.08 ns, TNS -1063 ns, 928 failing endpoints, 55.3 MHz |
| Setup `mclk` | +1.81 ns |
| Hold | +0.076 ns |
| Power | 31.7 mW |
| IR drop | 2.89 mV |
| Antenna | 0 |
| DRC / LVS | clean |

The ten worst paths start at instruction register bits and end in the register file. A case analysis that holds instruction bit 25 (the M opcode bit) at 0 takes the multiplier and divider out of the timing graph:

| | WNS (ns) | Failing endpoints |
|---|---|---|
| With M | -3.08 | 928 |
| Without M | -1.78 | 757 |

The multiplier costs 1.3 ns. The rest of the core also misses 15 ns.

Decision: split the multiplier over two cycles.

## Two-cycle multiplier

The first cycle registers four 17x17 partial products of the 33-bit operands (134 flops). The second adds them and writes the result. A multiply now takes one extra cycle: the warm benchmark goes from 10,347 to 10,859 cycles, 512 more for its 512 multiplies.

Review of the stall logic found a bug in the M extension: the divider started while EX was waiting for a load, so `lw t3, ...; div t1, t3, t2` divided the old `t3`. Check 51 does exactly that and fails on that RTL. The divider and the multiplier now wait until no load is pending on their operands. RTL and gate-level simulation pass all 52 checks.

The post-CTS estimate improves from -11.08 to -0.89 ns. After global routing, `repair_timing` sees -4.5 ns, inserts 1532 buffers and upsizes 2526 cells; with the single-cycle multiplier the same step upsized 1539 cells and inserted no buffers. Detailed routing started at 74,062 violations (before: 46,339) and still had 38,134 after six passes and 44 minutes, and was stopped.

The estimate after global routing has been pessimistic every time since it was introduced. These pairs are on nearly the same netlist, before and after detailed routing:

| WNS after global routing (ns) | Signoff WNS (ns) |
|---|---|
| -0.59 | +5.69 |
| -0.60 | +3.39 |
| -0.24 | +2.14 |
| -0.46 | +1.96 |
| -9.16 | -3.08 |

Decision: keep `repair_design` after global routing, and run `repair_timing` there without buffer insertion.

## Resize-only timing repair after global routing

