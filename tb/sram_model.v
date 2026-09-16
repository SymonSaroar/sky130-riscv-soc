// Simulation model of sky130_sram_2kbyte_1rw1r_32x512_8: inputs registered on posedge, dout X 1 ns after
// posedge, valid 0.53 ns after negedge (the largest clock-to-dout in the liberty).
module sky130_sram_2kbyte_1rw1r_32x512_8 (
  input             clk0, csb0, web0,
  input       [3:0] wmask0,
  input       [8:0] addr0,
  input      [31:0] din0,
  output reg [31:0] dout0,
  input             clk1, csb1,
  input       [8:0] addr1,
  output reg [31:0] dout1
);
  reg [31:0] mem [0:511];
  reg        cs0, we0, cs1;
  reg  [3:0] wm0;
  reg  [8:0] a0, a1;
  reg [31:0] d0;
  integer i;

  always @(posedge clk0) begin
    {cs0, we0, wm0, a0, d0} <= {!csb0, !web0, wmask0, addr0, din0};
    dout0 <= #1 32'bx;
  end
  always @(posedge clk1) begin
    {cs1, a1} <= {!csb1, addr1};
    dout1 <= #1 32'bx;
  end

  always @(negedge clk0) if (cs0) begin
    if (we0) for (i = 0; i < 4; i = i + 1) begin
      if (wm0[i]) mem[a0][i*8 +: 8] <= d0[i*8 +: 8];
    end
    else dout0 <= #0.53 mem[a0];
  end
  always @(negedge clk1) if (cs1) dout1 <= #0.53 mem[a1];
endmodule
