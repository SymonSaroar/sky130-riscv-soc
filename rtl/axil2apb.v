// AXI4-Lite to APB bridge. Six zero-wait slaves selected by paddr[14:12].
module axil2apb (
  input              clk,
  input              rst,
  input       [31:0] awaddr,
  input              awvalid,
  output             awready,
  input       [31:0] wdata,
  input              wvalid,
  output             wready,
  output             bvalid,
  input              bready,
  input       [31:0] araddr,
  input              arvalid,
  output             arready,
  output reg  [31:0] rdata,
  output             rvalid,
  input              rready,
  output reg  [31:0] paddr,
  output reg         pwrite,
  output reg  [31:0] pwdata,
  output       [5:0] psel,
  output             penable,
  input      [191:0] prdata
);
  localparam IDLE = 2'd0, SETUP = 2'd1, ACCESS = 2'd2, RESP = 2'd3;
  reg [1:0] st;

  wire wr = awvalid && wvalid;
  assign awready = st == IDLE && wr;
  assign wready  = awready;
  assign arready = st == IDLE && arvalid && !wr;
  assign penable = st == ACCESS;
  assign psel    = st == SETUP || st == ACCESS ? 6'b1 << paddr[14:12] : 6'b0;
  assign rvalid  = st == RESP && !pwrite;
  assign bvalid  = st == RESP && pwrite;

  always @(posedge clk)
    if (rst) st <= IDLE;
    else case (st)
      IDLE: if (awready || arready) begin
        st     <= SETUP;
        pwrite <= wr;
        paddr  <= wr ? awaddr : araddr;
        pwdata <= wdata;
      end
      SETUP:  st <= ACCESS;
      ACCESS: begin st <= RESP; rdata <= prdata[paddr[14:12]*32 +: 32]; end
      RESP:   if (rvalid && rready || bvalid && bready) st <= IDLE;
    endcase
endmodule
