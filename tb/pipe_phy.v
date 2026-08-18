// PIPE PHY model: settles 64 clocks after reset, always detects a receiver,
// reports the partner's electrical idle. Data passes straight between the MACs.
module pipe_phy (
  input             pclk,
  input             reset_n,
  input             tx_detect_rx,
  input             partner_elecidle,
  output reg        phy_status,
  output reg [11:0] rx_status,
  output      [3:0] rx_elecidle
);
  reg [5:0] cnt;
  assign rx_elecidle = {4{partner_elecidle}};
  always @(posedge pclk or negedge reset_n)
    if (!reset_n) begin phy_status <= 1'b1; cnt <= 0; rx_status <= 0; end
    else begin
      rx_status <= 0;
      if (cnt != 6'd63) begin cnt <= cnt + 1; phy_status <= 1'b1; end
      else if (tx_detect_rx && !phy_status) begin phy_status <= 1'b1; rx_status <= {4{3'b011}}; end
      else phy_status <= 1'b0;
    end
endmodule
