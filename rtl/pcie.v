// PCIe port: AXI4-Lite slave and APB status on clk, transaction layer and link on pclk.
// One memory request in flight: MWr32 or MRd32 of one DW, completed by the Ack or the CplD.
module pcie (
  input          clk,
  input          rst,
  input   [31:0] awaddr,
  input          awvalid,
  output         awready,
  input   [31:0] wdata,
  input    [3:0] wstrb,
  input          wvalid,
  output         wready,
  output         bvalid,
  input          bready,
  input   [31:0] araddr,
  input          arvalid,
  output         arready,
  output  [31:0] rdata,
  output         rvalid,
  input          rready,
  // APB status register: {replays[7:0], ltssm[2:0], link_up}
  output  [31:0] prdata,
  // PIPE, pclk domain
  input          pclk,
  input          prst,
  output [127:0] tx_data,
  output  [15:0] tx_datak,
  output         tx_elecidle,
  output         tx_detect_rx,
  output   [1:0] power_down,
  input  [127:0] rx_data,
  input   [15:0] rx_datak,
  input    [3:0] rx_elecidle,
  input   [11:0] rx_status,
  input          phy_status
);
  // ---------------- clk side ----------------
  reg  busy, pend_wr;
  wire wr = awvalid && wvalid;
  wire cfull, rempty;
  assign awready = !busy && !cfull && wr;
  assign wready  = awready;
  assign arready = !busy && !cfull && arvalid && !wr;
  assign rvalid  = busy && !rempty && !pend_wr;
  assign bvalid  = busy && !rempty && pend_wr;
  wire   resp_ok = rvalid && rready || bvalid && bready;

  always @(posedge clk)
    if (rst) begin busy <= 1'b0; pend_wr <= 1'b0; end
    else if (awready || arready) begin busy <= 1'b1; pend_wr <= wr; end
    else if (resp_ok) busy <= 1'b0;

  wire        link_up;
  wire  [2:0] ltssm;
  wire  [7:0] replays;
  reg  [11:0] st1, st2;
  always @(posedge clk) {st2, st1} <= {st1, replays, ltssm, link_up};
  assign prdata = {20'b0, st2};

  // ---------------- clock crossing ----------------
  wire        c_empty, r_push;
  reg         c_pop;
  wire [68:0] c_data;
  reg  [31:0] r_data;

  async_fifo #(.W(69)) u_cmd (
    .wclk(clk), .wrst(rst), .winc(awready || arready),
    .wdata({wr, wr ? awaddr : araddr, wdata, wstrb}), .wfull(cfull),
    .rclk(pclk), .rrst(prst), .rinc(c_pop), .rdata(c_data), .rempty(c_empty)
  );

  async_fifo #(.W(32)) u_rsp (
    .wclk(pclk), .wrst(prst), .winc(r_push), .wdata(r_data), .wfull(),
    .rclk(clk), .rrst(rst), .rinc(resp_ok), .rdata(rdata), .rempty(rempty)
  );

  // ---------------- transaction layer, pclk ----------------
  localparam [1:0] T_IDLE = 0, T_SEND = 1, T_WAIT = 2;
  reg   [1:0] st;
  reg         t_we;
  reg  [31:0] t_addr, t_wd;
  reg   [3:0] t_be;
  wire        t_ready, t_done, r_valid;
  wire [127:0] r_tlp;
  reg         rsp;
  assign r_push = rsp;

  // MWr32 (Fmt 010) or MRd32 (Fmt 000), length 1, requester 0, tag 0
  wire [127:0] t_tlp = {t_wd,
                        t_addr[7:2], 2'b00, t_addr[15:8], t_addr[23:16], t_addr[31:24],
                        4'h0, t_we ? t_be : 4'hF, 8'h00, 16'h0000,
                        8'h01, 8'h00, 8'h00, t_we ? 8'h40 : 8'h00};
  wire cpld = r_valid && r_tlp[7:0] == 8'h4A && r_tlp[87:80] == 8'h00;

  always @(posedge pclk) begin
    c_pop <= 1'b0;
    rsp   <= 1'b0;
    if (prst) st <= T_IDLE;
    else case (st)
      T_IDLE: if (!c_empty && !c_pop) begin
        {t_we, t_addr, t_wd, t_be} <= c_data;
        c_pop <= 1'b1;
        st    <= T_SEND;
      end
      T_SEND: if (t_ready) st <= T_WAIT;
      default: begin
        if (t_we && t_done) begin rsp <= 1'b1; r_data <= 32'b0; st <= T_IDLE; end
        if (!t_we && cpld)  begin rsp <= 1'b1; r_data <= r_tlp[127:96]; st <= T_IDLE; end
      end
    endcase
  end

  pcie_mac #(.ROOT(1)) u_mac (
    .clk(pclk), .rst(prst),
    .tx_data(tx_data), .tx_datak(tx_datak), .tx_elecidle(tx_elecidle), .tx_detect_rx(tx_detect_rx),
    .power_down(power_down), .rx_data(rx_data), .rx_datak(rx_datak), .rx_elecidle(rx_elecidle),
    .rx_status(rx_status), .phy_status(phy_status),
    .t_valid(st == T_SEND), .t_len16(t_we), .t_data(t_tlp), .t_ready(t_ready), .t_done(t_done),
    .r_valid(r_valid), .r_data(r_tlp),
    .link_up(link_up), .ltssm(ltssm), .replays(replays)
  );
endmodule
