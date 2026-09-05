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
  output reg        cke,
  output reg        cs_n,
  output reg        ras_n,
  output reg        cas_n,
  output reg        we_n,
  output reg  [1:0] ba,
  output reg [12:0] a,
  output reg  [1:0] dqm,
  output reg [15:0] dq_out,
  output reg        dq_oe,
  input      [15:0] dq_in
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
    if (rst) begin busy <= 1'b0; pend_wr <= 1'b0; end
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

  wire        p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_dq_oe;
  wire  [1:0] p_ba, p_dqm;
  wire [12:0] p_a;
  wire [15:0] p_dq_out;
  reg  [15:0] dq_n;

  sdram_ctrl u_ctrl (
    .clk(mclk), .rst(mrst),
    .c_valid(!c_empty), .c_data(c_data), .c_pop(c_pop),
    .r_push(r_push), .r_data(r_data),
    .cke(p_cke), .cs_n(p_cs_n), .ras_n(p_ras_n), .cas_n(p_cas_n), .we_n(p_we_n),
    .ba(p_ba), .a(p_a), .dqm(p_dqm), .dq_out(p_dq_out), .dq_oe(p_dq_oe), .dq_in(dq_n)
  );

  // pins change on the falling edge of mclk; the SDRAM samples on the next rising edge.
  // Read data is captured on the falling edge too, a cycle and a half after the SDRAM clock edge.
  always @(negedge mclk) begin
    {cke, cs_n, ras_n, cas_n, we_n, ba, a, dqm, dq_out, dq_oe} <=
      {p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_ba, p_a, p_dqm, p_dq_out, p_dq_oe};
    dq_n <= dq_in;
  end
endmodule
