// Instruction cache for SDRAM code: direct-mapped, 64 lines of 32 bytes, data in a 2 KB SRAM macro.
// Lookup has the same timing as the SRAM: address in one cycle, data and hit the next.
// A miss refills the line with 8 AXI4-Lite reads.
module icache (
  input             clk,
  input             rst,
  input      [31:0] addr,         // fetch address, sampled every cycle
  output     [31:0] rdata,
  output            hit,          // for the address of the previous cycle
  // AXI4-Lite master, read only
  output     [31:0] araddr,
  output            arvalid,
  input             arready,
  input      [31:0] rdata_m,
  input             rvalid,
  output            rready
);
  reg  [31:0] q;                  // address being looked up
  reg  [13:0] tag [0:63];
  reg  [63:0] valid;
  wire  [5:0] qi = q[10:5];
  assign hit = valid[qi] && tag[qi] == q[24:11];

  // refill
  reg         fill, ar_wait, done;
  reg  [26:0] line;               // address[31:5] of the line being filled
  reg   [2:0] k;                  // word in the line
  assign araddr  = {line, k, 2'b00};
  assign arvalid = ar_wait;
  assign rready  = 1'b1;
  wire   wr      = fill && rvalid;

  always @(posedge clk) begin
    q <= addr;
    if (rst) begin
      valid   <= 64'b0;
      fill    <= 1'b0;
      ar_wait <= 1'b0;
      done    <= 1'b0;
    end else begin
      done <= 1'b0;
      if (done) valid[line[5:0]] <= 1'b1;     // one cycle after the last word is written
      if (!fill && !done && q[31] && !hit) begin
        fill    <= 1'b1;
        ar_wait <= 1'b1;
        line    <= q[31:5];
        k       <= 3'd0;
        valid[qi] <= 1'b0;
        tag[qi]   <= q[24:11];
      end else if (fill) begin
        if (arvalid && arready) ar_wait <= 1'b0;
        if (wr) begin
          k <= k + 1;
          if (k == 3'd7) begin fill <= 1'b0; done <= 1'b1; end
          else ar_wait <= 1'b1;
        end
      end
    end
  end

  sky130_sram_2kbyte_1rw1r_32x512_8 mem (
    .clk0   (clk),
    .csb0   (!wr),
    .web0   (1'b0),
    .wmask0 (4'hf),
    .addr0  ({line[5:0], k}),
    .din0   (rdata_m),
    .dout0  (),
    .clk1   (clk),
    .csb1   (rst),
    .addr1  (addr[10:2]),
    .dout1  (rdata)
  );
endmodule
