`timescale 1ns/1ps
module tb_soc;
  localparam BIT = 434 * 20;

  reg  clk = 0, rst_n = 0, uart_rx = 1;
  wire uart_tx, spi_cs_n, spi_sclk, spi_mosi, spi_miso;
  wire [15:0] gpio_out, gpio_oe;
  always #10 clk = !clk;

  soc_top dut (
    .clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
    .gpio_in(16'h0), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso)
  );
  spi_flash flash (.cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso));

  integer i, j;
  reg [7:0] c, d;

  initial begin
    if ($test$plusargs("vcd")) begin $dumpfile("tb_soc.vcd"); $dumpvars(0, tb_soc); end
    #200 rst_n = 1;
    #20_000_000 $display("TIMEOUT pc=%h", dut.u_cpu.pc); $finish;
  end

  // UART monitor
  always @(negedge uart_tx) begin
    #(BIT * 3 / 2);
    for (i = 0; i < 8; i = i + 1) begin c[i] = uart_tx; #BIT; end
    $write("%c", c);
  end

  // send 'Z' when firmware asks for it
  initial begin
    wait (gpio_out == 16'h00a0);
    d = "Z";
    uart_rx = 0; #BIT;
    for (j = 0; j < 8; j = j + 1) begin uart_rx = d[j]; #BIT; end
    uart_rx = 1;
  end

  always @(gpio_out) if (gpio_out[15:8] == 8'ha5) begin
    $display("\n%s at %0t ns", gpio_out[0] ? "TEST PASSED" : "TEST FAILED", $time);
    $finish;
  end
endmodule
