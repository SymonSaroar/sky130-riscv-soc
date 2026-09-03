`timescale 1ns/1ps
module tb_soc;
  localparam BIT = 868 * 10;

  reg  clk_r = 0, mclk_r = 0, rst_r = 0, rx_r = 1;
  wire clk = clk_r, mclk = mclk_r, rst_n = rst_r, uart_rx = rx_r;
  wire uart_tx, spi_cs_n, spi_sclk, spi_mosi, spi_miso;
  wire [15:0] gpio;
  pulldown gpio_pd [15:0] (gpio);
  always #5 clk_r = !clk_r;
  always #5 mclk_r = !mclk_r;

  wire        sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
  wire  [1:0] sdram_ba, sdram_dqm;
  wire [12:0] sdram_a;
  wire [15:0] dq;

`ifndef GLS
  supply1 vccd, vddio, vdda;
  supply0 vssd, vssio, vssa;
`endif
  chip_top dut (
`ifndef GLS
    .vccd(vccd), .vssd(vssd), .vddio(vddio), .vssio(vssio), .vdda(vdda), .vssa(vssa),
`endif
    .clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx), .gpio(gpio),
    .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
    .mclk(mclk), .sdram_clk(sdram_clk), .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n),
    .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
    .sdram_ba(sdram_ba), .sdram_a(sdram_a), .sdram_dqm(sdram_dqm), .sdram_dq(dq)
  );
  sdram_model sdram (
    .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n), .ras_n(sdram_ras_n), .cas_n(sdram_cas_n),
    .we_n(sdram_we_n), .ba(sdram_ba), .a(sdram_a), .dqm(sdram_dqm), .dq(dq)
  );
  spi_flash flash (.cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso));

  integer i, j;
  reg [7:0] c, d;

  initial begin
    if ($test$plusargs("vcd")) begin $dumpfile("tb_soc.vcd"); $dumpvars(0, tb_soc); end
    #200 rst_r = 1;
`ifdef GLS
    #40_000_000 $display("TIMEOUT"); $finish;
`else
    #40_000_000 $display("TIMEOUT pc=%h", dut.u_core.u_cpu.pc); $finish;
`endif
  end

  // UART monitor
  always @(negedge uart_tx) begin
    #(BIT * 3 / 2);
    for (i = 0; i < 8; i = i + 1) begin c[i] = uart_tx; #BIT; end
    $write("%c", c);
  end

  // send 'Z' when firmware asks for it
  initial begin
    wait (gpio === 16'h00a0);
    d = "Z";
    rx_r = 0; #BIT;
    for (j = 0; j < 8; j = j + 1) begin rx_r = d[j]; #BIT; end
    rx_r = 1;
  end

  always @(gpio) if (gpio[15:8] === 8'ha5) begin
    $display("\n%s at %0t ns (SDRAM protocol errors: %0d)",
             gpio[0] && sdram.errors == 0 ? "TEST PASSED" : "TEST FAILED", $time, sdram.errors);
    $finish;
  end
endmodule
