// PCIe endpoint for the testbench: the link layer in endpoint mode and a 1 KB memory
// that takes MWr32 and answers MRd32 with CplD.
module pcie_ep (
  input          pclk,
  input          reset_n,
  output [127:0] tx_data,
  output  [15:0] tx_datak,
  output         tx_elecidle,
  output         tx_detect_rx,
  input  [127:0] rx_data,
  input   [15:0] rx_datak,
  input    [3:0] rx_elecidle,
  input   [11:0] rx_status,
  input          phy_status
);
  reg [1:0] rs;
  always @(posedge pclk) rs <= {rs[0], reset_n};

  reg  [31:0] mem [0:255];
  wire        t_ready, r_valid;
  wire [127:0] r;
  reg         t_valid;
  reg  [127:0] cpl;
  integer     i;

  wire [7:0] idx = {r[81:80], r[95:90]};    // address bits 9:2 from header bytes 10 and 11
  always @(posedge pclk) begin
    if (t_ready) t_valid <= 1'b0;
    if (!rs[1]) t_valid <= 1'b0;
    else if (r_valid && r[7:0] == 8'h40) begin
      for (i = 0; i < 4; i = i + 1) if (r[56 + i]) mem[idx][i * 8 +: 8] <= r[96 + i * 8 +: 8];
    end else if (r_valid && r[7:0] == 8'h00) begin
      // CplD: completer 0x0100, status 0, byte count 4, requester 0, tag, lower address
      cpl <= {mem[idx], 1'b0, r[94:88], r[55:48], 16'h0000, 8'h04, 8'h00, 8'h00, 8'h01,
              8'h01, 8'h00, 8'h00, 8'h4A};
      t_valid <= 1'b1;
    end
  end

  pcie_mac #(.ROOT(0)) u_mac (
    .clk(pclk), .rst(!rs[1]),
    .tx_data(tx_data), .tx_datak(tx_datak), .tx_elecidle(tx_elecidle), .tx_detect_rx(tx_detect_rx),
    .power_down(), .rx_data(rx_data), .rx_datak(rx_datak), .rx_elecidle(rx_elecidle),
    .rx_status(rx_status), .phy_status(phy_status),
    .t_valid(t_valid), .t_len16(1'b1), .t_data(cpl), .t_ready(t_ready), .t_done(),
    .r_valid(r_valid), .r_data(r), .link_up(), .ltssm(), .replays()
  );
endmodule
