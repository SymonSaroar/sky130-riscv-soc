// 2 KB SRAM. Port 0 (RW) is an AXI4-Lite slave, port 1 (R) serves instruction fetch.
module sram_axil (
  input         clk,
  input         rst,
  input  [31:0] awaddr,
  input         awvalid,
  output        awready,
  input  [31:0] wdata,
  input   [3:0] wstrb,
  input         wvalid,
  output        wready,
  output reg    bvalid,
  input         bready,
  input  [31:0] araddr,
  input         arvalid,
  output        arready,
  output [31:0] rdata,
  output reg    rvalid,
  input         rready,
  input  [31:0] i_addr,
  output [31:0] i_rdata
);
  reg  [8:0] ra;
  wire       wr  = awvalid && wvalid && !bvalid;
  wire       rd  = arvalid && !rvalid;
  wire       hold = rvalid && !rready;        // read again so dout stays valid
  assign awready = wr;
  assign wready  = wr;
  assign arready = rd;

  always @(posedge clk) begin
    if (rst) begin
      rvalid <= 1'b0;
      bvalid <= 1'b0;
    end else begin
      if (rd) ra <= araddr[10:2];
      rvalid <= rd || hold;
      bvalid <= wr || (bvalid && !bready);
    end
  end

  sky130_sram_2kbyte_1rw1r_32x512_8 mem (
    .clk0   (clk),
    .csb0   (!(wr || rd || hold)),
    .web0   (!wr),
    .wmask0 (wstrb),
    .addr0  (wr ? awaddr[10:2] : rd ? araddr[10:2] : ra),
    .din0   (wdata),
    .dout0  (rdata),
    .clk1   (clk),
    .csb1   (rst),
    .addr1  (i_addr[10:2]),
    .dout1  (i_rdata)
  );
endmodule
