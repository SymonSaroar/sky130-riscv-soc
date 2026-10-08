// PIPE registers for the PHY macro, 32 bits per pclk with symbol 0 in bits 7:0. pclk is the PHY's MaxPCLK through
// the clock tree, which also clocks the PHY's PCLK pin. One RxStatus, RxValid and PhyStatus per clock stand for both
// 16-bit words of the MAC side.
module pcie_pipe (
  input             arst,          // asynchronous: chip reset or the PHY held in reset
  input             pclk,
  input      [31:0] rx_data,
  input       [3:0] rx_datak,
  input       [2:0] rx_status,
  input             rx_valid,
  input             phy_status,
  input             rx_elecidle,
  output reg [31:0] tx_data,
  output reg  [3:0] tx_datak,
  output reg        tx_elecidle,
  output reg        tx_compliance,
  output reg        tx_det_lb,
  output reg        rx_polarity,
  output reg  [1:0] powerdown,
  // MAC side: symbol 0 in bits 7:0
  output            prst,
  output reg [31:0] r_data,
  output reg  [3:0] r_k,
  output reg  [5:0] r_st,          // RxStatus of the low and high word
  output reg  [1:0] r_val,
  output reg  [1:0] r_phys,
  output reg        r_ei,
  input      [31:0] t_data,
  input       [3:0] t_k,
  input       [1:0] t_comp,
  input             t_ei,
  input             t_det,
  input             t_pol,
  input       [1:0] t_pd
);
  // reset: asserted at once, released on the second pclk edge
  reg [1:0] pr;
  always @(posedge pclk or posedge arst)
    if (arst) pr <= 2'b00; else pr <= {pr[0], 1'b1};
  assign prst = !pr[1];

  always @(posedge pclk) begin
    r_data <= rx_data;
    r_k    <= rx_datak;
    r_st   <= {2{rx_status}};
    r_val  <= {2{rx_valid}};
    r_phys <= {2{phy_status}};
    r_ei   <= rx_elecidle;
    tx_data  <= t_data;
    tx_datak <= t_k;
  end

  // control pins at their PIPE reset values while the PHY is in reset: P1, electrical idle
  always @(posedge pclk or posedge arst)
    if (arst) {powerdown, rx_polarity, tx_det_lb, tx_elecidle, tx_compliance} <= {2'b10, 1'b0, 1'b0, 1'b1, 1'b0};
    else {powerdown, rx_polarity, tx_det_lb, tx_elecidle, tx_compliance} <= {t_pd, t_pol, t_det, t_ei, t_comp[0]};
endmodule
