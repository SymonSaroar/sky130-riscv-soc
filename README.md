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
  +--------+   +------------------------------------------+
  |  boot  |-->|        AXI4-Lite interconnect             |
  | loader |   +------------------------------------------+
  +--------+                          |
      |                               v
   SPI flash                    AXI4-Lite to APB
                                      |
               +--------+------+------+------+-------+
               |  UART  | GPIO | SPI  | timer| INTC  |
               +--------+------+------+------+-------+
```

Details are in [docs/spec_v1.md](docs/spec_v1.md).

## Results

All numbers come from `reports/metrics.csv`, which `make metrics` updates. Timing is at the typical corner (tt, 25 C, 1.8 V) with OpenRCX parasitics, clock 20 ns.

<!-- metrics -->
| run | wns_ns | tns_ns | whs_ns | viol_endpoints | fmax_mhz | util_pct | power_mw | grt_congestion | route_drc | magic_drc | klayout_drc | lvs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01-baseline | -10.063 | -9075.234 | 0.076 | 1210 | 33.3 | 52 | 8.98 | 0 | 0 | 1943 | 0 | mismatch |
| 02-sram-corner | - | - | - | - | - | 52 | - | 4290 | - | - | - | - |
| 03-sram-channels | -8.855 | -8749.597 | 0.084 | 1218 | 34.7 | 52 | 9.10 | 0 | 0 | 0 | 0 | mismatch |
| 04-cts-setup-repair | - | - | - | - | - | 53 | - | 0 | - | - | - | - |
| 05-placement-padding | -3.677 | -3405.824 | 0.077 | 1209 | 42.2 | 53 | 9.53 | 0 | 0 | 0 | 0 | clean |
| 06-instruction-register | -4.744 | -4707.600 | 0.083 | 1275 | 40.4 | 52 | 9.72 | 0 | 0 | 0 | 0 | clean |
| 07-load-use-stall | -0.226 | -2.867 | 0.083 | 19 | 49.4 | 52 | 9.92 | 0 | 0 | 0 | 0 | clean |
<!-- /metrics -->

## Journal

- [Boot and peripherals](docs/journal/boot-and-peripherals.md)

## Layout of the repo

| Path | Contents |
|---|---|
| `rtl/` | SoC RTL |
| `tb/` | Testbench, flash and SRAM models, firmware |
| `constraints/` | SDC |
| `synthesis/` | Yosys script |
| `floorplan/`, `placement/`, `cts/`, `routing/` | OpenROAD stage scripts |
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
