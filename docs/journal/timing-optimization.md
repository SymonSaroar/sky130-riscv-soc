# Timing optimization

Spec: [spec_v5.md](../spec_v5.md). The system clock target moves from 66.7 to 100 MHz (10 ns). The UART divisor becomes 868, and the delay limit on crossings between `clk` and `pclk` becomes 10 ns. RTL simulation passes. The benchmark takes 11,555 cycles cold and 10,859 warm; cold grows because a cache refill from SDRAM now costs more `clk` cycles.

| Change | Setup WNS clk / mclk / pclk (ns) | Failing endpoints | Hold WNS (ns) | DRC / LVS |
|---|---|---|---|---|
| `clk` at 10 ns | -4.11 / +2.28 / +5.30 | 1904 | +0.075 | clean |

## 10 ns

Synthesis gives the same netlist as before, gate for gate: the ABC delay target follows the clock, and 10 ns maps the same as 15 ns.

`clk` misses by 4.11 ns (70.9 MHz) on 1904 endpoints. `mclk`, `pclk` and hold close, DRC and LVS are clean, and power is 63.3 mW. Every failing path starts at the EX instruction register: decode, register file read, then the ALU or an adder. They end in the register file (992), in the PCIe and SDRAM command FIFOs through the interconnect (508), at the fetch address, in the CSRs and in the multiplier's partial products.

The worst paths also carry delay chains. Timing repair after CTS builds chains of `buf_1` cells with one load each, up to 39 in a row. The longest before the PCIe port was 4; with it there were already 45, hidden by the 15 ns clock.

A candidate with a register-read stage and the bus request driven from registers ran through CTS at -3.68 ns, against -7.17 ns without it. Its worst path ran from the multiplier's partial products through their 66-bit sum, the new forwarding mux and into an operand register.

Decision: a register-read stage between ID and EX with forwarding from EX, the bus request driven from WB registers, and the multiply sum registered before writeback.
