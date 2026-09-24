// TI-PIPE front end on pipe_rx_clk (125 MHz, two symbols per clock). Receive pins are captured on the falling
// edge, then on the rising edge, and two words are paired into four symbols for pclk. pclk is pipe_rx_clk divided
// by 2 in a flop; words cross on the rising edge where pclk falls, half a pclk period from either pclk edge.
// Transmit words leave falling-edge registers, low half first.
module pcie_pipe (
  input             arst,          // asynchronous: chip reset or the PHY held in reset
  input             rx_clk,
  input      [15:0] rx_data,
  input       [1:0] rx_datak,
  input       [2:0] rx_status,
  input             rx_valid,
  input             phy_status,
  input             rx_elecidle,
  output reg [15:0] tx_data,
  output reg  [1:0] tx_datak,
  output reg        tx_elecidle,
  output reg        tx_compliance,
  output reg        tx_det_lb,
  output reg        rx_polarity,
  output reg  [1:0] powerdown,
  // pclk side: symbol 0 in bits 7:0
  output            pclk,
  output            prst,
  output reg [31:0] r_data,
  output reg  [3:0] r_k,
  output reg  [5:0] r_st,          // RX_STATUS of the low and high word
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
  // resets: asserted at once, released on the clock they reset
  reg [1:0] rr, pr;
  reg       ph;
  always @(posedge rx_clk or posedge arst)
    if (arst) rr <= 2'b00; else rr <= {rr[0], 1'b1};
  wire rrst = !rr[1];
  always @(posedge rx_clk or posedge arst)
    if (arst) ph <= 1'b0; else if (rrst) ph <= 1'b0; else ph <= !ph;
  assign pclk = ph;
  always @(posedge pclk or posedge arst)
    if (arst) pr <= 2'b00; else pr <= {pr[0], 1'b1};
  assign prst = !pr[1];

  // receive: {data, k, status, valid, phy_status, elecidle} per word
  reg [23:0] rx_n, rx_p, rx_q;
  reg [47:0] rx2;
  always @(negedge rx_clk) rx_n <= {rx_data, rx_datak, rx_status, rx_valid, phy_status, rx_elecidle};
  always @(posedge rx_clk) begin
    rx_p <= rx_n;
    rx_q <= rx_p;
    if (ph) rx2 <= {rx_p, rx_q};
  end
  always @(posedge pclk) begin
    r_data <= {rx2[47:32], rx2[23:8]};
    r_k    <= {rx2[31:30], rx2[7:6]};
    r_st   <= {rx2[29:27], rx2[5:3]};
    r_val  <= {rx2[26], rx2[2]};
    r_phys <= {rx2[25], rx2[1]};
    r_ei   <= rx2[24];
  end

  // transmit
  reg [42:0] tw;
  always @(posedge rx_clk or posedge arst)
    if (arst) tw <= {2'b10, 1'b0, 1'b0, 1'b1, 38'b0};
    else if (ph) tw <= {t_pd, t_pol, t_det, t_ei, t_comp, t_k, t_data};
  always @(negedge rx_clk or posedge arst)
    if (arst) begin
      tx_data <= 16'b0; tx_datak <= 2'b0; tx_compliance <= 1'b0;
      tx_elecidle <= 1'b1; tx_det_lb <= 1'b0; rx_polarity <= 1'b0; powerdown <= 2'b10;
    end else begin
      tx_data       <= ph ? tw[31:16] : tw[15:0];
      tx_datak      <= ph ? tw[35:34] : tw[33:32];
      tx_compliance <= ph ? tw[37] : tw[36];
      tx_elecidle   <= tw[38];
      tx_det_lb     <= tw[39];
      rx_polarity   <= tw[40];
      powerdown     <= tw[42:41];
    end
endmodule
