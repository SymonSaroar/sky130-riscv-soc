`timescale 1ns/1ps
module tb_soc;
  localparam BIT = 868 * 10;

  reg  clk = 0, mclk = 0, rst_n = 0, uart_rx = 1;
  wire uart_tx, spi_cs_n, spi_sclk, spi_mosi, spi_miso;
  wire [15:0] gpio_out, gpio_oe;
  always #5 clk = !clk;
  always #5 mclk = !mclk;

  wire        sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_dq_oe;
  wire  [1:0] sdram_ba, sdram_dqm;
  wire [12:0] sdram_a;
  wire [15:0] sdram_dq_out;
  wire [15:0] dq = sdram_dq_oe ? sdram_dq_out : 16'bz;

  // PCIe: SoC root port and endpoint model, back to back through two PHY models
  reg          pclk = 0;
  always #8 pclk = !pclk;
  wire [127:0] soc_tx, ep_tx;
  wire  [15:0] soc_txk, ep_txk;
  wire         soc_ei, ep_ei, soc_det, ep_det, soc_phys, ep_phys, pipe_reset_n;
  wire  [11:0] soc_rxst, ep_rxst;
  wire   [3:0] soc_rxei, ep_rxei;
  pipe_phy phy_soc (.pclk(pclk), .reset_n(pipe_reset_n), .tx_detect_rx(soc_det), .partner_elecidle(ep_ei),
                    .phy_status(soc_phys), .rx_status(soc_rxst), .rx_elecidle(soc_rxei));
  pipe_phy phy_ep  (.pclk(pclk), .reset_n(pipe_reset_n), .tx_detect_rx(ep_det), .partner_elecidle(soc_ei),
                    .phy_status(ep_phys), .rx_status(ep_rxst), .rx_elecidle(ep_rxei));
  pcie_ep ep (.pclk(pclk), .reset_n(pipe_reset_n), .tx_data(ep_tx), .tx_datak(ep_txk), .tx_elecidle(ep_ei),
              .tx_detect_rx(ep_det), .rx_data(soc_tx), .rx_datak(soc_txk), .rx_elecidle(ep_rxei),
              .rx_status(ep_rxst), .phy_status(ep_phys));

  soc_top dut (
    .clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
    .gpio_in(16'h0), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
    .mclk(mclk), .sdram_clk(sdram_clk), .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n),
    .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
    .sdram_ba(sdram_ba), .sdram_a(sdram_a), .sdram_dqm(sdram_dqm),
    .sdram_dq_out(sdram_dq_out), .sdram_dq_oe(sdram_dq_oe), .sdram_dq_in(dq),
    .pclk(pclk), .pipe_tx_data(soc_tx), .pipe_tx_datak(soc_txk), .pipe_tx_elecidle(soc_ei),
    .pipe_tx_detect_rx(soc_det), .pipe_power_down(), .pipe_reset_n(pipe_reset_n),
    .pipe_rx_data(ep_tx), .pipe_rx_datak(ep_txk), .pipe_rx_elecidle(soc_rxei),
    .pipe_rx_status(soc_rxst), .pipe_phy_status(soc_phys)
  );
  sdram_model sdram (
    .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n), .ras_n(sdram_ras_n), .cas_n(sdram_cas_n),
    .we_n(sdram_we_n), .ba(sdram_ba), .a(sdram_a), .dqm(sdram_dqm), .dq(dq)
  );
  spi_flash flash (.cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso));

  integer i, j;

`ifndef GLS
  // the link CRC is the reflected CRC-32: check value 0xCBF43926 for "123456789"
  initial begin : crc_check
    reg [31:0] c; integer n;
    c = 32'hFFFFFFFF;
    for (n = 0; n < 9; n = n + 1) c = dut.u_pcie.u_mac.crc32_byte(c, 8'h31 + n);
    if (~c !== 32'hCBF43926) begin $display("CRC-32 CHECK FAILED %h", ~c); $finish; end
  end
`endif
  reg [7:0] c, d;

  initial begin
    if ($test$plusargs("vcd")) begin $dumpfile("tb_soc.vcd"); $dumpvars(0, tb_soc); end
    #200 rst_n = 1;
`ifdef GLS
    #40_000_000 $display("TIMEOUT"); $finish;
`else
    #40_000_000 $display("TIMEOUT pc=%h", dut.u_cpu.pc); $finish;
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
    wait (gpio_out == 16'h00a0);
    d = "Z";
    uart_rx = 0; #BIT;
    for (j = 0; j < 8; j = j + 1) begin uart_rx = d[j]; #BIT; end
    uart_rx = 1;
  end

  always @(gpio_out) if (gpio_out[15:8] == 8'ha5) begin
    $display("\n%s at %0t ns (SDRAM protocol errors: %0d)",
             gpio_out[0] && sdram.errors == 0 ? "TEST PASSED" : "TEST FAILED", $time, sdram.errors);
    $finish;
  end
endmodule
