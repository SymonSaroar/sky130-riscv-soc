# PCIe x4 on SKY130

## The physical layer stays off-chip

PCIe Gen1 runs each lane at 2.5 GT/s with 8b/10b coding: a 2.5 Gb/s serial stream, or 250 M symbols per second per lane. That needs a SerDes with a PLL, clock and data recovery, and current-mode line drivers. The open SKY130 PDK has no such macro, and its standard cells close at about 100 to 150 MHz in this design.

Decision: an external PHY chip handles the serial side. The SoC holds the link and transaction layers and talks to the PHY over PIPE.

## PIPE width

| Width per lane | PCLK | Data pins (x4, both directions) |
|---|---|---|
| 8 bits | 250 MHz | 72 |
| 16 bits | 125 MHz | 144 |
| 32 bits | 62.5 MHz | 288 |

Decision: 32 bits at 62.5 MHz.

## Pins

| Group | Pins |
|---|---|
| `pipe_tx_data`, `pipe_rx_data` | 256 |
| `pipe_tx_datak`, `pipe_rx_datak` | 32 |
| `pipe_rx_status` | 12 |
| `pipe_rx_elecidle` | 4 |
| `pclk`, `pipe_reset_n`, `pipe_phy_status`, `pipe_tx_elecidle`, `pipe_tx_detect_rx` | 5 |
| `pipe_power_down` | 2 |
| Total | 311 |

The macro goes from 113 to 424 pins.

## Scope

| Implemented | Not implemented |
|---|---|
| LTSSM: Detect, Polling.Active, Polling.Configuration, Configuration, L0 | Recovery, L0s, L1, L2, hot reset, link width negotiation below x4 |
| TS1/TS2 with link and lane numbers, SKP ordered sets every 320 clocks | Lane deskew, lane reversal, polarity inversion |
| Byte striping, STP/SDP/END framing | Packets starting mid-block, EDB, nullified TLPs |
| Scrambling disabled through the TS training control bit | The scrambler |
| Sequence numbers, LCRC (reflected CRC-32), Ack/Nak, replay timer | More than one unacknowledged TLP |
| InitFC1/InitFC2 with infinite credits | UpdateFC, credit accounting |
| MWr32 and MRd32 of one DW from the CPU, CplD back | Configuration requests, I/O requests, messages, inbound requests, more than one outstanding read |

## Verification

The testbench connects the SoC to a second copy of the link layer in endpoint mode through two PIPE PHY models, with a 1 KB memory behind the endpoint. The firmware waits for the link, writes eight words and a byte, and reads them back. The LCRC function matches the CRC-32 check value 0xCBF43926 for "123456789". A flipped LCRC bit, rotated receive lanes, or a wrong Ack sequence number each make the test fail.

Both ends run the same link code, so the test shows the two ends agree with each other, not that they agree with the PCIe specification.
