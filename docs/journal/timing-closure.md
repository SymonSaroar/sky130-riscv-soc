# Timing closure

Goal: close 50 MHz at tt_025C_1v80 on the design as it stands.

## Where the slack goes

Worst setup slack with placement padding, by path group:

| Path group | Worst slack (ns) |
|---|---|
| Through SRAM `dout1` (instruction fetch) | -3.68 |
| Into SRAM `addr1` (next fetch address) | -3.46 |
| Through SRAM `dout0` (load data forwarded into EX) | -2.95 |
| Failing endpoints that do not start at the SRAM | 0 of 1209 |

The SRAM launches both read ports on the falling clock edge. Every failing path gets half a cycle.

Decision: fix it in the RTL.

| Change | WNS (ns) | TNS (ns) | Failing endpoints | DRC / LVS |
|---|---|---|---|---|
| Instruction register | -4.74 | -4708 | 1275 | clean |
| Load-use stall instead of load forwarding | -0.23 | -2.9 | 19 | clean |
| Wire capacitance calibrated to OpenRCX | | | | |

## Instruction register

The fetched word goes into an instruction register at the rising edge, and decode starts from there. A taken branch or jump now costs one cycle.

`repair_design` stopped with RSZ-0090. The SRAM liberty gives its address and data inputs a 40 ps `max_transition`, the top of the macro's characterization range, and the best a sky130_fd_sc_hd driver reaches on those nets is 46 ps. The nets into the SRAM inputs are now dont_touch during `repair_design`. STA still reports the limit.

| Path group | Before | Instruction register |
|---|---|---|
| Through `dout1` | -3.68 | +9.11 |
| Into `addr1` | -3.46 | -3.77 |
| Through `dout0` | -2.95 | -4.74 |

The fetch path is fixed. Every failing path now starts at `dout0`: load data forwarded into the ALU, the branch target and the next fetch address.

Decision: drop load forwarding. An instruction that reads a register still being loaded waits one cycle.

## Load-use stall

The SRAM read data now only feeds the load alignment and the register file write. Every path through the core starts and ends on a rising edge.

WNS is -0.23 ns, TNS -2.9 ns, 19 failing endpoints, 49.4 MHz. DRC and LVS are clean.

The worst path runs from an instruction register flop through the register file read, the ALU and the register file write. Most of its delay sits in small cells on long nets. One `or2_0` drives 0.21 pF and takes 2.34 ns.

The estimates before routing do not match signoff. On the routed database, placement-based parasitics give WNS +5.55 ns and OpenRCX gives -0.23 ns. Over 769 sampled nets, extracted wire capacitance is 2.40 times the estimate. Net `_04613_` has 13 loads over 300 µm: 0.070 pF estimated, 0.180 pF extracted. Setup repair after CTS sizes cells for the smaller number.

The estimate uses met2 from the tech LEF: 8.93e-4 kΩ/µm and 77.9e-6 pF/µm.

Decision: estimate signal wires at 8.93e-4 kΩ/µm and 1.87e-4 pF/µm (2.40 x 77.9e-6).

## Calibrated wire capacitance

