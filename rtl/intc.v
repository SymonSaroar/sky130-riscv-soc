// Interrupt controller for level sources. Regs: 0x0 PENDING (ro), 0x4 ENABLE.
module intc #(parameter N = 2) (
  input             clk,
  input             rst,
  input             psel,
  input             penable,
  input             pwrite,
  input       [3:2] paddr,
  input      [31:0] pwdata,
  output     [31:0] prdata,
  input     [N-1:0] src,
  output            irq
);
  reg [N-1:0] en;
  assign prdata = paddr[2] ? en : src;
  assign irq    = |(src & en);

  always @(posedge clk)
    if (rst) en <= 0;
    else if (psel && penable && pwrite && paddr == 2'd1) en <= pwdata[N-1:0];
endmodule
