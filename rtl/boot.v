// Boot loader: reads 2 KB from SPI flash (cmd 0x03, addr 0) into SRAM over AXI4-Lite, then sets done.
module boot (
  input             clk,
  input             rst,
  output reg        done,
  // AXI4-Lite master, write only
  output     [31:0] awaddr,
  output            awvalid,
  input             awready,
  output     [31:0] wdata,
  output            wvalid,
  input             wready,
  input             bvalid,
  output            bready,
  // SPI
  output            cs_n,
  output            sclk,
  output            mosi,
  input             miso
);
  localparam START = 2'd0, XFER = 2'd1, WRITE = 2'd2, RESP = 2'd3;
  localparam BYTES = 2048 + 4;

  reg  [1:0] st;
  reg [11:0] n;              // bytes done, including the 4 command bytes
  reg [31:0] word;
  wire       sdone;
  wire [7:0] rx;

  assign awaddr  = {20'b0, n - 12'd8};     // n has already moved past the word
  assign awvalid = st == WRITE;
  assign wvalid  = st == WRITE;
  assign wdata   = word;
  assign bready  = 1'b1;
  assign cs_n    = done;

  always @(posedge clk)
    if (rst) begin
      st   <= START;
      n    <= 0;
      done <= 1'b0;
    end else if (!done) case (st)
      START: st <= XFER;
      XFER: if (sdone) begin
        n    <= n + 1;
        word <= {rx, word[31:8]};
        st   <= n >= 4 && n[1:0] == 2'd3 ? WRITE : START;
      end
      WRITE: if (awready && wready) st <= RESP;
      RESP: if (bvalid) begin
        if (n == BYTES) done <= 1'b1;
        st <= START;
      end
    endcase

  spi_byte u_byte (
    .clk(clk), .rst(rst), .start(st == START && !done), .din(n == 0 ? 8'h03 : 8'h00),
    .busy(), .done(sdone), .dout(rx), .sclk(sclk), .mosi(mosi), .miso(miso)
  );
endmodule
