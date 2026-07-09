// SPI flash model: READ (0x03) only, mode 0.
module spi_flash #(parameter HEX = "build/fw/fw.hex") (
  input      cs_n,
  input      sclk,
  input      mosi,
  output reg miso
);
  reg [7:0] mem [0:4095];
  reg [31:0] cmd;
  integer bits, i;
  initial begin
    for (i = 0; i < 4096; i = i + 1) mem[i] = 8'hff;
    $readmemh(HEX, mem);
  end

  always @(negedge cs_n) bits = 0;
  always @(posedge sclk) if (!cs_n) begin
    if (bits < 32) cmd = {cmd[30:0], mosi};
    bits = bits + 1;
  end
  always @(negedge sclk) if (!cs_n && bits >= 32)
    miso = mem[cmd[23:0] + (bits - 32) / 8][7 - (bits - 32) % 8];
endmodule
