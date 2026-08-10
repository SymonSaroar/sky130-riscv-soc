# Complete RTL-to-GDSII implementation and timing closure of a small SoC

A RISC-V SoC taken from RTL to GDSII on SKY130 with open-source tools. Each result of the flow is committed with its reports, and the journal records what it showed and what changed next.

## The SoC

```
            +----------+   fetch (SRAM port 1)   +-------------------+
            |  RV32I   |------------------------>|   2 KB SRAM       |
            |  core    |                         |   (OpenRAM macro) |
            +----------+                         +-------------------+
                 | AXI4-Lite                              ^ port 0
                 v                                        |
  +--------+   +------------------------------------------+-----------+
  |  boot  |-->|              AXI4-Lite interconnect                  |
  | loader |   +------------------------------------------------------+
  +--------+                  |                              |
      |                       v                              v
   SPI flash            AXI4-Lite to APB          async FIFOs (clk -> mclk)
                              |                              |
       +--------+------+------+------+-------+     SDRAM controller (100 MHz)
       |  UART  | GPIO | SPI  | timer| INTC  |               |
       +--------+------+------+------+-------+       32 MB SDR SDRAM
```

Details are in [docs/spec_v3.md](docs/spec_v3.md).

## Results

All numbers come from `reports/metrics.csv`, which `make metrics` updates. Timing is at the typical corner (tt, 25 C, 1.8 V) with OpenRCX parasitics. `clk` is 20 ns; from row 11 on, `mclk` is 10 ns.

<!-- metrics -->
| run | wns_ns | tns_ns | whs_ns | viol_endpoints | hold_viol | fmax_mhz | wns_mclk_ns | fmax_mclk_mhz | slew_viol | slew_waived | cap_viol | antenna_nets | power_mw | ir_drop_mv | grt_congestion | route_drc | magic_drc | klayout_drc | lvs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01-baseline | -10.063 | -9075.234 | 0.076 | 1210 | - | 33.3 | - | - | 3384 | 22 | 156 | 65 | 8.98 | - | 0 | 0 | 1943 | 0 | mismatch |
| 02-sram-corner | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 4290 | - | - | - | - |
| 03-sram-channels | -8.855 | -8749.597 | 0.084 | 1218 | - | 34.7 | - | - | 3941 | 22 | 190 | 48 | 9.10 | - | 0 | 0 | 0 | 0 | mismatch |
| 04-cts-setup-repair | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 0 | - | - | - | - |
| 05-placement-padding | -3.677 | -3405.824 | 0.077 | 1209 | - | 42.2 | - | - | 1834 | 22 | 145 | 102 | 9.53 | - | 0 | 0 | 0 | 0 | clean |
| 06-instruction-register | -4.744 | -4707.600 | 0.083 | 1275 | - | 40.4 | - | - | 2388 | 22 | 147 | 78 | 9.72 | - | 0 | 0 | 0 | 0 | clean |
| 07-load-use-stall | -0.226 | -2.867 | 0.083 | 19 | - | 49.4 | - | - | 2763 | 22 | 203 | 62 | 9.92 | - | 0 | 0 | 0 | 0 | clean |
| 08-wire-rc-calibration | 2.777 | 0.000 | 0.084 | 0 | - | 58.1 | - | - | 207 | 22 | 37 | 84 | 9.90 | - | 0 | 0 | 0 | 0 | clean |
| 09-sram-input-buffers | 4.237 | 0.000 | 0.083 | 0 | - | 63.4 | - | - | 150 | 22 | 22 | 84 | 9.98 | - | 0 | 0 | 0 | 0 | clean |
| 10-grt-repair | 5.691 | 0.000 | 0.079 | 0 | - | 69.9 | - | - | 0 | 22 | 0 | 64 | 11.50 | - | 0 | 0 | 0 | 0 | clean |
| 11-sdram-port | 3.394 | 0.000 | -0.256 | 0 | 32 | 68.4 | 3.394 | 151.4 | 0 | 22 | 0 | 58 | 16.20 | - | 0 | 0 | 0 | 0 | clean |
| 12-hold-repair | 3.385 | 0.000 | -0.222 | 0 | 32 | 68.4 | 3.385 | 151.2 | 0 | 22 | 0 | 48 | 16.20 | - | 0 | 0 | 0 | 0 | clean |
| 13-sdram-falling-edge | 2.144 | 0.000 | 0.074 | 0 | 0 | 64.5 | 2.144 | 127.3 | 0 | 22 | 0 | 74 | 16.90 | - | 1 | 0 | 0 | 0 | clean |
| 14-cdc-constraints | 2.144 | 0.000 | 0.074 | 0 | 0 | 64.5 | 2.144 | 127.3 | 0 | 22 | 0 | 74 | 16.90 | - | 1 | 0 | 0 | 0 | clean |
| 15-antenna-repair | 2.144 | 0.000 | 0.074 | 0 | 0 | 64.5 | 2.144 | 127.3 | 0 | 22 | 0 | 0 | 16.90 | - | 1 | 0 | 0 | 0 | clean |
| 16-util-60 | 1.967 | 0.000 | 0.069 | 0 | 0 | 65.3 | 1.967 | 124.5 | 0 | 22 | 0 | 2 | 16.70 | - | 0 | 0 | 0 | 0 | clean |
| 17-antenna-passes | 1.967 | 0.000 | 0.069 | 0 | 0 | 65.3 | 1.967 | 124.5 | 0 | 22 | 0 | 0 | 16.70 | - | 0 | 0 | 0 | 0 | clean |
| 18-power-pins-ir | 1.963 | 0.000 | 0.070 | 0 | 0 | 65.8 | 1.963 | 124.4 | 0 | 22 | 0 | 1 | 16.70 | 1.60 | 0 | 0 | 0 | 0 | clean |
| 19-antenna-buffers | 1.964 | 0.000 | 0.070 | 0 | 0 | 65.7 | 1.964 | 124.4 | 0 | 22 | 0 | 0 | 16.70 | 1.60 | 0 | 0 | 0 | 0 | clean |
| 20-rv32m-icache | -3.079 | -1062.946 | 0.076 | 928 | 0 | 55.3 | 1.808 | 122.1 | 0 | 44 | 0 | 0 | 31.70 | 2.89 | 0 | 0 | 0 | 0 | clean |
| 21-two-cycle-mul | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 0 | - | - | - | - |
| 22-resize-only-repair | - | - | - | - | - | - | - | - | - | - | - | - | - | - | 0 | - | - | - | - |
<!-- /metrics -->

## Journal

- [Boot and peripherals](docs/journal/boot-and-peripherals.md)
- [Timing closure](docs/journal/timing-closure.md)
- [External memory](docs/journal/external-memory.md)
- [Place and route cleanup](docs/journal/place-and-route-cleanup.md)

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
