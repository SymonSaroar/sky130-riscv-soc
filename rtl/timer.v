// Machine timer. Regs: 0x0 MTIME, 0x4 MTIMECMP. irq = mtime >= mtimecmp.
module timer (
  input         clk,
  input         rst,
  input         psel,
  input         penable,
  input         pwrite,
  input   [3:2] paddr,
  input  [31:0] pwdata,
  output [31:0] prdata,
  output        irq
);
  reg [31:0] mtime, mtimecmp;
  wire wr = psel && penable && pwrite;
  assign prdata = paddr[2] ? mtimecmp : mtime;
  assign irq    = mtime >= mtimecmp;

  always @(posedge clk)
    if (rst) begin
      mtime    <= 32'b0;
      mtimecmp <= 32'hffffffff;
    end else begin
      mtime <= wr && paddr == 2'd0 ? pwdata : mtime + 1;
      if (wr && paddr == 2'd1) mtimecmp <= pwdata;
    end
endmodule
