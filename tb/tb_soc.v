`timescale 1ns/1ps
module tb_soc #(parameter real CLK_HALF = 5, MCLK_HALF = 5);
  localparam real BIT = 868 * 2 * CLK_HALF;

  reg  clk_r = 0, mclk_r = 0, rst_r = 0, rx_r = 1;
  wire clk = clk_r, mclk = mclk_r, rst_n = rst_r, uart_rx = rx_r;
  wire uart_tx, spi_cs_n, spi_sclk, spi_mosi, spi_miso;
  wire [15:0] gpio;
  pulldown gpio_pd [15:10] (gpio[15:10]);
  pulldown gpio_pl [7:0] (gpio[7:0]);
  always #CLK_HALF clk_r = !clk_r;
  always #MCLK_HALF mclk_r = !mclk_r;

  wire        sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
  wire  [1:0] sdram_ba, sdram_dqm;
  wire [12:0] sdram_a;
  wire [15:0] dq;

  // PCIe: the XIO1100 model and an endpoint model behind it. gpio[8] pulled high tells the firmware that faults are
  // injected (+pcie_faults), so it reports link errors instead of failing on them; gpio[9] (+pcie_hot_reset) adds a
  // Hot Reset and a second enumeration.
  wire        rx_clk, tx_clk, rx_valid, phy_status, rx_ei, tx_ei, tx_comp, tx_det, rx_pol, phy_rst_n;
  wire [15:0] rx_data, tx_data;
  wire  [1:0] rx_datak, tx_datak, powerdown;
  wire  [2:0] rx_status;
  wire  [7:0] lt_sym, lr_sym;
  wire        lt_k, lt_idle, lt_stb, lr_k, lr_idle, lr_stb;
  reg         pcie_faults, pcie_hot;
  initial pcie_faults = $test$plusargs("pcie_faults");
  initial pcie_hot = $test$plusargs("pcie_hot_reset");
  assign (pull0, pull1) gpio[8] = pcie_faults;
  assign (pull0, pull1) gpio[9] = pcie_hot;
  xio1100 phy (
    .reset_n(phy_rst_n), .powerdown(powerdown), .tx_clk(tx_clk), .tx_data(tx_data), .tx_datak(tx_datak),
    .tx_elecidle(tx_ei), .tx_compliance(tx_comp), .tx_det_lb(tx_det), .rx_polarity(rx_pol),
    .rx_clk(rx_clk), .rx_data(rx_data), .rx_datak(rx_datak), .rx_status(rx_status), .rx_valid(rx_valid),
    .phy_status(phy_status), .rx_elecidle(rx_ei),
    .lt_sym(lt_sym), .lt_k(lt_k), .lt_idle(lt_idle), .lt_stb(lt_stb),
    .lr_sym(lr_sym), .lr_k(lr_k), .lr_idle(lr_idle), .lr_stb(lr_stb)
  );
  pcie_dev dev (
    .perst_n(rst_n), .tx_sym(lr_sym), .tx_k(lr_k), .tx_idle(lr_idle), .tx_stb(lr_stb),
    .rx_sym(lt_sym), .rx_k(lt_k), .rx_idle(lt_idle), .rx_stb(lt_stb)
  );

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
    .sdram_ba(sdram_ba), .sdram_a(sdram_a), .sdram_dqm(sdram_dqm), .sdram_dq(dq),
    .pipe_rx_clk(rx_clk), .pipe_rx_data(rx_data), .pipe_rx_datak(rx_datak), .pipe_rx_status(rx_status),
    .pipe_rx_valid(rx_valid), .pipe_phy_status(phy_status), .pipe_rx_elecidle(rx_ei),
    .pipe_tx_clk(tx_clk), .pipe_tx_data(tx_data), .pipe_tx_datak(tx_datak), .pipe_tx_elecidle(tx_ei),
    .pipe_tx_compliance(tx_comp), .pipe_tx_det_loopback(tx_det), .pipe_rx_polarity(rx_pol),
    .pipe_powerdown(powerdown), .pipe_reset_n(phy_rst_n)
  );
  sdram_model sdram (
    .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n), .ras_n(sdram_ras_n), .cas_n(sdram_cas_n),
    .we_n(sdram_we_n), .ba(sdram_ba), .a(sdram_a), .dqm(sdram_dqm), .dq(dq)
  );
  spi_flash flash (.cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso));

`ifdef SDF
  initial $sdf_annotate(`SDF, dut);
`endif

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

  // +progress=<file>: simulated time in us, rewritten every 100 us
  reg [8*256-1:0] progress;
  integer pf;
  initial if ($value$plusargs("progress=%s", progress))
    forever begin
      #100_000;
      pf = $fopen(progress, "w");
      $fdisplay(pf, "%0d", $time / 1000);
      $fclose(pf);
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

  // the result, once every pad has switched
  always @(gpio) if (gpio[15:8] === 8'ha5) begin
    #100;
    $display("\n%s at %0d ns (SDRAM protocol errors: %0d, PHY violations: %0d, endpoint violations: %0d)",
             gpio[0] && sdram.errors == 0 && phy.errors == 0 && dev.errors == 0 ? "TEST PASSED" : "TEST FAILED",
             $time, sdram.errors, phy.errors, dev.errors);
    $finish;
  end
endmodule
