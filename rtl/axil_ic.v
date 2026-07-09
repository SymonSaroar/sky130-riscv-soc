// AXI4-Lite interconnect: 2 masters, 2 slaves, one transaction at a time.
// Fixed priority (M0 first). Slave select: addr[28] (0 = SRAM, 1 = peripherals).
// Masters assert AW and W together; slaves accept them together.
module axil_ic (
  input         clk,
  input         rst,
  // masters, packed {m1, m0}
  input  [63:0] m_awaddr,
  input   [1:0] m_awvalid,
  output  [1:0] m_awready,
  input  [63:0] m_wdata,
  input   [7:0] m_wstrb,
  input   [1:0] m_wvalid,
  output  [1:0] m_wready,
  output  [1:0] m_bvalid,
  input   [1:0] m_bready,
  input  [63:0] m_araddr,
  input   [1:0] m_arvalid,
  output  [1:0] m_arready,
  output [31:0] m_rdata,
  output  [1:0] m_rvalid,
  input   [1:0] m_rready,
  // slaves, packed {s1, s0}
  output [31:0] s_awaddr,
  output  [1:0] s_awvalid,
  input   [1:0] s_awready,
  output [31:0] s_wdata,
  output  [3:0] s_wstrb,
  output  [1:0] s_wvalid,
  input   [1:0] s_wready,
  input   [1:0] s_bvalid,
  output  [1:0] s_bready,
  output [31:0] s_araddr,
  output  [1:0] s_arvalid,
  input   [1:0] s_arready,
  input  [63:0] s_rdata,
  input   [1:0] s_rvalid,
  output  [1:0] s_rready
);
  reg busy, gq, sq;

  // address phase
  wire g  = !(m_arvalid[0] || m_awvalid[0]);
  wire wr = m_awvalid[g];
  assign s_awaddr = m_awaddr[g*32 +: 32];
  assign s_araddr = m_araddr[g*32 +: 32];
  assign s_wdata  = m_wdata[g*32 +: 32];
  assign s_wstrb  = m_wstrb[g*4 +: 4];
  wire   s  = wr ? s_awaddr[28] : s_araddr[28];

  wire av = !busy && m_arvalid[g];
  wire wv = !busy && m_awvalid[g] && m_wvalid[g];
  assign s_arvalid = {av && s, av && !s};
  assign s_awvalid = {wv && s, wv && !s};
  assign s_wvalid  = s_awvalid;

  wire ar_ok = av && s_arready[s];
  wire aw_ok = wv && s_awready[s] && s_wready[s];
  assign m_arready = ar_ok ? 2'b1 << g : 2'b0;
  assign m_awready = aw_ok ? 2'b1 << g : 2'b0;
  assign m_wready  = m_awready;

  // response phase
  assign m_rdata  = s_rdata[sq*32 +: 32];
  assign m_rvalid = busy && s_rvalid[sq] ? 2'b1 << gq : 2'b0;
  assign m_bvalid = busy && s_bvalid[sq] ? 2'b1 << gq : 2'b0;
  assign s_rready = busy ? {2{m_rready[gq]}} & (2'b1 << sq) : 2'b0;
  assign s_bready = busy ? {2{m_bready[gq]}} & (2'b1 << sq) : 2'b0;

  always @(posedge clk)
    if (rst) busy <= 1'b0;
    else if (ar_ok || aw_ok) begin busy <= 1'b1; gq <= g; sq <= s; end
    else if (|(m_rvalid & m_rready) || |(m_bvalid & m_bready)) busy <= 1'b0;
endmodule
