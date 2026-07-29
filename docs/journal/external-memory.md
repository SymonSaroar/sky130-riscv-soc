# External memory

Spec: [spec_v2.md](../spec_v2.md). Adds a 32 MB SDR SDRAM at `0x8000_0000`, driven by a controller on a second clock, `mclk` at 100 MHz. The system clock stays at 50 MHz.

The bus side is an AXI4-Lite slave on `clk`. Commands and responses cross to `mclk` through two async FIFOs with Gray-coded pointers. Each 32-bit word is one ACTIVE plus a READ or WRITE with auto-precharge and a burst of 2.

The testbench has an SDRAM model that checks protocol rules. The firmware writes and reads back 16 words in four rows across three banks, then checks byte and halfword stores. RTL and gate-level simulation pass with 0 protocol errors. Two deliberate bugs make the test fail: capturing read data one cycle early, and dropping auto-precharge (290 protocol errors).

The SDRAM pins are timed against the forwarded clock `sdram_clk` with MT48LC16M16A2-75 numbers: tIS 1.5 ns, tIH 0.8 ns, tAC 5.4 ns, tOH 2.7 ns, and a 1 ns board round trip. The two clock domains are asynchronous.

| Change | Setup WNS clk / mclk (ns) | Hold WNS (ns) | Hold failures | DRC / LVS |
|---|---|---|---|---|
| SDRAM port | +5.38 / +3.39 | -0.256 | 32 | clean |
| Hold repair | | | | |

## SDRAM port

The die grows to 921 x 921 µm. Power rises from 11.5 to 16.2 mW.

Setup closes in both domains: 68.4 MHz for `clk` and 151 MHz for `mclk`.

Hold fails on 32 endpoints, all of them SDRAM outputs. On `sdram_cas_n`, the launching flop's clock arrives at 1.19 ns through four levels of the `mclk` tree, and the pin switches at 1.57 ns. The forwarded clock leaves the die through a shorter path and reaches `sdram_clk` at 0.76 ns. The SDRAM needs the old value held until 0.76 + 0.8 + 0.25 = 1.81 ns.

The flow has no hold repair.

Decision: run `repair_timing -hold` after CTS and after global routing.

## Hold repair
