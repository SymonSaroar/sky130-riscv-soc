// SDRAM port: AXI4-Lite slave on clk, controller on mclk, async FIFOs between them.
module sdram (
  input         clk,
  input         rst,
  input  [31:0] awaddr,
  input         awvalid,
  output        awready,
  input  [31:0] wdata,
  input   [3:0] wstrb,
  input         wvalid,
  output        wready,
  output        bvalid,
  input         bready,
  input  [31:0] araddr,
  input         arvalid,
  output        arready,
  output [31:0] rdata,
  output        rvalid,
  input         rready,
  // memory clock domain
  input         mclk,
  input         mrst,
  output        cke,
  output        cs_n,
  output        ras_n,
  output        cas_n,
  output        we_n,
  output  [1:0] ba,
  output [12:0] a,
  output  [1:0] dqm,
  output [15:0] dq_out,
  output        dq_oe,
  input  [15:0] dq_in
);
  // one transaction in flight
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
    if (rst) busy <= 1'b0;
    else if (awready || arready) begin busy <= 1'b1; pend_wr <= wr; end
    else if (resp_ok) busy <= 1'b0;

  wire        c_empty, c_pop, r_push;
  wire [59:0] c_data;
  wire [31:0] r_data;

  async_fifo #(.W(60)) u_cmd (
    .wclk(clk), .wrst(rst), .winc(awready || arready),
    .wdata({wr, wr ? awaddr[24:2] : araddr[24:2], wdata, wstrb}), .wfull(cfull),
    .rclk(mclk), .rrst(mrst), .rinc(c_pop), .rdata(c_data), .rempty(c_empty)
  );

  async_fifo #(.W(32)) u_rsp (
    .wclk(mclk), .wrst(mrst), .winc(r_push), .wdata(r_data), .wfull(),
    .rclk(clk), .rrst(rst), .rinc(resp_ok), .rdata(rdata), .rempty(rempty)
  );

  sdram_ctrl u_ctrl (
    .clk(mclk), .rst(mrst),
    .c_valid(!c_empty), .c_data(c_data), .c_pop(c_pop),
    .r_push(r_push), .r_data(r_data),
    .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
    .ba(ba), .a(a), .dqm(dqm), .dq_out(dq_out), .dq_oe(dq_oe), .dq_in(dq_in)
  );
endmodule
