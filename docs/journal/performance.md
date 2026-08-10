# Performance push

Spec: [spec_v3.md](../spec_v3.md). The CPU gains the M extension, code runs from SDRAM through a 2 KB instruction cache in a second SRAM macro, and the system clock target moves from 50 to 66.7 MHz (15 ns).

The firmware boots in two stages. A 292-byte loader in SRAM copies the program from SPI flash into SDRAM and jumps to it. That program runs 50 RV32IM checks (14 of them for the M extension, including divide by zero and -2^31 / -1), the interrupt, SPI and SDRAM tests, and an 8x8 matrix multiply with divides whose products are checked against shift-and-add. RTL and gate-level simulation pass with 0 SDRAM protocol errors. Marking a cache line valid when its refill starts makes the test hang at `0x80000000`.

The benchmark takes 10,937 cycles cold and 10,347 warm.

| Change | Setup WNS clk / mclk (ns) | Failing endpoints | Hold WNS (ns) | DRC / LVS |
|---|---|---|---|---|
| M extension, instruction cache, 15 ns clock | -3.08 / +1.81 | 928 | +0.076 | clean |

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
