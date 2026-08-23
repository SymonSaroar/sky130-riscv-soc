# Complete RTL-to-GDSII implementation and timing closure of a small SoC

A RISC-V SoC taken from RTL to GDSII on SKY130 with open-source tools. Each result of the flow is committed with its reports, and the journal records what it showed and what changed next.

## The SoC

```
                fetch below 0x8000_0000     +----------------+
   +----------+---------------------------->| 2 KB SRAM      |---+ port 0
   | RV32IM   |                             +----------------+   |
   | core     |---------------------------->| 2 KB I-cache   |---+ refill
   +----------+ fetch from 0x8000_0000      +----------------+   |
        | AXI4-Lite                                              |
        v                                                        v
  +--------------------------------------------------------------------------+
  |                        AXI4-Lite interconnect                            |
  +--------------------------------------------------------------------------+
     ^ boot loader           |                    |                    |
     |                       v                    v                    v
  SPI flash         AXI4-Lite to APB     async FIFOs (clk/mclk)  async FIFOs (clk/pclk)
                             |                    |                    |
       +------+------+-----+-------+------+  SDRAM controller     PCIe Gen1 x4 link
       | UART | GPIO | SPI | timer | INTC |   (100 MHz)            (62.5 MHz, PIPE)
       +------+------+-----+-------+------+       |                    |
                                           32 MB SDR SDRAM      external PCIe PHY
```

Details are in [docs/spec_v4.md](docs/spec_v4.md).

## Results

All numbers come from `reports/metrics.csv`, which `make metrics` updates. Timing is at the typical corner (tt, 25 C, 1.8 V) with OpenRCX parasitics. `clk` is 20 ns up to row 19 and 15 ns from row 20; `mclk` is 10 ns from row 11; `pclk` is 16 ns from row 26.

<!-- metrics -->
| run | place_density | wns_ns | tns_ns | whs_ns | viol_endpoints | hold_viol | fmax_mhz | wns_mclk_ns | fmax_mclk_mhz | wns_pclk_ns | fmax_pclk_mhz | slew_viol | slew_waived | cap_viol | antenna_nets | power_mw | ir_drop_mv | grt_congestion | route_drc | magic_drc | klayout_drc | lvs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01-baseline | 0.6000 | -10.063 | -9075.234 | 0.076 | 1210 | - | 33.3 | - | - | - | - | 3384 | 22 | 156 | 65 | 8.98 | - | 0 | 0 | 1943 | 0 | mismatch |
| 02-sram-corner | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 4290 | - | - | - | - |
| 03-sram-channels | 0.6000 | -8.855 | -8749.597 | 0.084 | 1218 | - | 34.7 | - | - | - | - | 3941 | 22 | 190 | 48 | 9.10 | - | 0 | 0 | 0 | 0 | mismatch |
| 04-cts-setup-repair | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 0 | - | - | - | - |
| 05-placement-padding | 0.6000 | -3.677 | -3405.824 | 0.077 | 1209 | - | 42.2 | - | - | - | - | 1834 | 22 | 145 | 102 | 9.53 | - | 0 | 0 | 0 | 0 | clean |
| 06-instruction-register | 0.6000 | -4.744 | -4707.600 | 0.083 | 1275 | - | 40.4 | - | - | - | - | 2388 | 22 | 147 | 78 | 9.72 | - | 0 | 0 | 0 | 0 | clean |
| 07-load-use-stall | 0.6000 | -0.226 | -2.867 | 0.083 | 19 | - | 49.4 | - | - | - | - | 2763 | 22 | 203 | 62 | 9.92 | - | 0 | 0 | 0 | 0 | clean |
| 08-wire-rc-calibration | 0.6000 | 2.777 | 0.000 | 0.084 | 0 | - | 58.1 | - | - | - | - | 207 | 22 | 37 | 84 | 9.90 | - | 0 | 0 | 0 | 0 | clean |
| 09-sram-input-buffers | 0.6000 | 4.237 | 0.000 | 0.083 | 0 | - | 63.4 | - | - | - | - | 150 | 22 | 22 | 84 | 9.98 | - | 0 | 0 | 0 | 0 | clean |
| 10-grt-repair | 0.6000 | 5.691 | 0.000 | 0.079 | 0 | - | 69.9 | - | - | - | - | 0 | 22 | 0 | 64 | 11.50 | - | 0 | 0 | 0 | 0 | clean |
| 11-sdram-port | 0.6000 | 3.394 | 0.000 | -0.256 | 0 | 32 | 68.4 | 3.394 | 151.4 | - | - | 0 | 22 | 0 | 58 | 16.20 | - | 0 | 0 | 0 | 0 | clean |
| 12-hold-repair | 0.6000 | 3.385 | 0.000 | -0.222 | 0 | 32 | 68.4 | 3.385 | 151.2 | - | - | 0 | 22 | 0 | 48 | 16.20 | - | 0 | 0 | 0 | 0 | clean |
| 13-sdram-falling-edge | 0.6000 | 2.144 | 0.000 | 0.074 | 0 | 0 | 64.5 | 2.144 | 127.3 | - | - | 0 | 22 | 0 | 74 | 16.90 | - | 1 | 0 | 0 | 0 | clean |
| 14-cdc-constraints | 0.6000 | 2.144 | 0.000 | 0.074 | 0 | 0 | 64.5 | 2.144 | 127.3 | - | - | 0 | 22 | 0 | 74 | 16.90 | - | 1 | 0 | 0 | 0 | clean |
| 15-antenna-repair | 0.6000 | 2.144 | 0.000 | 0.074 | 0 | 0 | 64.5 | 2.144 | 127.3 | - | - | 0 | 22 | 0 | 0 | 16.90 | - | 1 | 0 | 0 | 0 | clean |
| 16-util-60 | 0.7400 | 1.967 | 0.000 | 0.069 | 0 | 0 | 65.3 | 1.967 | 124.5 | - | - | 0 | 22 | 0 | 2 | 16.70 | - | 0 | 0 | 0 | 0 | clean |
| 17-antenna-passes | 0.7400 | 1.967 | 0.000 | 0.069 | 0 | 0 | 65.3 | 1.967 | 124.5 | - | - | 0 | 22 | 0 | 0 | 16.70 | - | 0 | 0 | 0 | 0 | clean |
| 18-power-pins-ir | 0.7400 | 1.963 | 0.000 | 0.070 | 0 | 0 | 65.8 | 1.963 | 124.4 | - | - | 0 | 22 | 0 | 1 | 16.70 | 1.60 | 0 | 0 | 0 | 0 | clean |
| 19-antenna-buffers | 0.7400 | 1.964 | 0.000 | 0.070 | 0 | 0 | 65.7 | 1.964 | 124.4 | - | - | 0 | 22 | 0 | 0 | 16.70 | 1.60 | 0 | 0 | 0 | 0 | clean |
| 20-rv32m-icache | 0.7300 | -3.079 | -1062.946 | 0.076 | 928 | 0 | 55.3 | 1.808 | 122.1 | - | - | 0 | 44 | 0 | 0 | 31.70 | 2.89 | 0 | 0 | 0 | 0 | clean |
| 21-two-cycle-mul | 0.7400 | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 0 | - | - | - | - |
| 22-resize-only-repair | 0.7400 | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 0 | - | - | - | - |
| 23-util-52 | 0.6000 | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 1 | - | - | - | - |
| 24-util-45 | 0.5000 | 2.078 | 0.000 | 0.080 | 0 | 0 | 78.8 | 2.078 | 126.2 | - | - | 0 | 44 | 1 | 0 | 33.90 | 3.09 | 0 | 0 | 0 | 0 | clean |
| 25-sram-output-buffers | 0.5000 | 2.036 | 0.000 | 0.080 | 0 | 0 | 77.6 | 2.036 | 125.6 | - | - | 0 | 44 | 1 | 0 | 33.90 | 3.08 | 0 | 0 | 0 | 0 | clean |
| 26-pcie-x4 | 0.5000 | 1.429 | 0.000 | 0.078 | 0 | 0 | 73.7 | 2.391 | 131.4 | 4.543 | 87.3 | 0 | 44 | 0 | 0 | 45.70 | 5.02 | 0 | 1 | 0 | 0 | clean |
| 27-pipe-falling-edge | 0.5100 | 0.880 | 0.000 | 0.067 | 0 | 0 | 70.8 | 2.277 | 129.5 | 5.551 | 95.7 | 0 | 44 | 0 | 1 | 47.30 | 2.45 | 0 | 0 | 0 | 0 | clean |
| 28-link-resets | 0.5100 | 0.927 | 0.000 | 0.078 | 0 | 0 | 71.1 | 2.259 | 129.2 | 5.313 | 93.6 | 0 | 44 | 0 | 3 | 47.50 | 4.08 | 0 | 0 | 0 | 0 | clean |
| 29-finish-diodes | 0.5100 | 0.928 | 0.000 | 0.078 | 0 | 0 | 71.1 | 2.259 | 129.2 | 5.313 | 93.6 | 0 | 44 | 0 | 0 | 47.50 | 4.08 | 0 | 0 | 0 | 0 | clean |
<!-- /metrics -->

## Journal

- [Boot and peripherals](docs/journal/boot-and-peripherals.md)
- [Timing closure](docs/journal/timing-closure.md)
- [External memory](docs/journal/external-memory.md)
- [Place and route cleanup](docs/journal/place-and-route-cleanup.md)
- [Performance push](docs/journal/performance.md)
- [PCIe adapter](docs/journal/pcie.md)

## Layout of the repo

| Path | Contents |
|---|---|
| `rtl/` | SoC RTL |
| `tb/` | Testbench, flash and SRAM models, firmware |
| `constraints/` | SDC |
| `synthesis/` | Yosys script |
| `floorplan/`, `placement/`, `cts/`, `routing/` | OpenROAD stage scripts |
| `power/` | Static IR drop |
| `extraction/` | OpenRCX |
| `sta/` | OpenSTA signoff timing and power |
| `signoff/` | KLayout stream-out, Magic DRC and extraction, Netgen LVS |
| `reports/<name>/` | Reports kept for each committed result |
| `docs/` | Spec and journal |

## Running it

```
make sim               # RTL simulation with firmware
make gls RUN=dev        # gate-level simulation of the synthesized netlist
make all RUN=dev        # synthesis through signoff, then metrics
make <stage> RUN=dev    # synth floorplan place cts route rcx sta gds lvs klayout_drc metrics
```

`PDK_ROOT` defaults to `~/.volare`. Build outputs go to `build/<RUN>/`.

## Tools

| Tool | Version |
|---|---|
| Yosys | 0.69+185 |
| OpenROAD | 26Q2-1164-g08f67ee5ec |
| OpenSTA | 3.1.0 |
| KLayout | 0.30.12 |
| Magic | 8.3.684 |
| Netgen | 1.5.324 |
| Icarus Verilog | 14.0 (devel) |
| Verilator | 5.053 |
| RISC-V GCC | 13.2.0 |
| SKY130 PDK (volare) | c6d73a35f524070e85faff4a6a9eef49553ebc2b |
