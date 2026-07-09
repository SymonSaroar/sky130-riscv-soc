// SPI master, mode 0, SCLK = clk/2. Regs: 0x0 CS (bit0 = cs_n), 0x4 DATA (wr: start byte, rd: last rx), 0x8 STATUS {busy}.
module spi (
  input             clk,
  input             rst,
  input             psel,
  input             penable,
  input             pwrite,
  input       [3:2] paddr,
  input      [31:0] pwdata,
  output reg [31:0] prdata,
  output reg        cs_n,
  output            sclk,
  output            mosi,
  input             miso,
  output            irq
);
  wire       wr = psel && penable && pwrite;
  wire       busy;
  wire [7:0] dout;
  assign irq = !busy;

  always @* case (paddr)
    2'd0:    prdata = {31'b0, cs_n};
    2'd1:    prdata = {24'b0, dout};
    default: prdata = {31'b0, busy};
  endcase

  always @(posedge clk)
    if (rst) cs_n <= 1'b1;
    else if (wr && paddr == 2'd0) cs_n <= pwdata[0];

  spi_byte u_byte (
    .clk(clk), .rst(rst), .start(wr && paddr == 2'd1), .din(pwdata[7:0]),
    .busy(busy), .done(), .dout(dout), .sclk(sclk), .mosi(mosi), .miso(miso)
  );
endmodule

// One byte, MSB first. done pulses for one cycle when dout is valid.
module spi_byte (
  input            clk,
  input            rst,
  input            start,
  input      [7:0] din,
  output           busy,
  output reg       done,
  output     [7:0] dout,
  output reg       sclk,
  output           mosi,
  input            miso
);
  reg [7:0] sh;
  reg [4:0] cnt;
  reg       b;
  assign busy = cnt != 0;
  assign mosi = sh[7];
  assign dout = sh;

  always @(posedge clk) begin
    done <= cnt == 1;
    if (rst) begin
      cnt  <= 0;
      sclk <= 1'b0;
    end else if (!busy) begin
      if (start) begin sh <= din; cnt <= 16; end
    end else begin
      cnt  <= cnt - 1;
      sclk <= !sclk;
      if (!sclk) b  <= miso;
      else       sh <= {sh[6:0], b};
    end
  end
endmodule
