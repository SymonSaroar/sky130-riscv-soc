// GPIO. Regs: 0x0 OUT, 0x4 IN, 0x8 OE.
module gpio (
  input             clk,
  input             rst,
  input             psel,
  input             penable,
  input             pwrite,
  input       [3:2] paddr,
  input      [31:0] pwdata,
  output reg [31:0] prdata,
  input      [15:0] gpio_in,
  output reg [15:0] gpio_out,
  output reg [15:0] gpio_oe
);
  reg [15:0] s1, s2;
  wire wr = psel && penable && pwrite;

  always @* case (paddr)
    2'd0:    prdata = {16'b0, gpio_out};
    2'd1:    prdata = {16'b0, s2};
    default: prdata = {16'b0, gpio_oe};
  endcase

  always @(posedge clk) begin
    s1 <= gpio_in;
    s2 <= s1;
    if (rst) begin
      gpio_out <= 16'b0;
      gpio_oe  <= 16'b0;
    end else if (wr) begin
      if (paddr == 2'd0) gpio_out <= pwdata[15:0];
      if (paddr == 2'd2) gpio_oe  <= pwdata[15:0];
    end
  end
endmodule
