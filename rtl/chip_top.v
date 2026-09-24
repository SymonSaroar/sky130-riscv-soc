// Chip top: the SoC core in a SKY130 pad ring of sky130_ef_io__gpiov2_pad_wrapped signal pads.
// VDDIO 3.3 V, VCCD 1.8 V. Supply pads, corners and bus slices are placed by the floorplan.
// The PCIe PHY inputs use the pads' 1.8 V input buffer.
module chip_top (
`ifdef USE_POWER_PINS
  inout         vccd,
  inout         vssd,
  inout         vddio,
  inout         vssio,
  inout         vdda,
  inout         vssa,
`endif
  input         clk,
  input         rst_n,
  output        uart_tx,
  input         uart_rx,
  inout  [15:0] gpio,
  output        spi_cs_n,
  output        spi_sclk,
  output        spi_mosi,
  input         spi_miso,
  input         mclk,
  output        sdram_clk,
  output        sdram_cke,
  output        sdram_cs_n,
  output        sdram_ras_n,
  output        sdram_cas_n,
  output        sdram_we_n,
  output  [1:0] sdram_ba,
  output [12:0] sdram_a,
  output  [1:0] sdram_dqm,
  inout  [15:0] sdram_dq,
  input         pipe_rx_clk,
  input  [15:0] pipe_rx_data,
  input   [1:0] pipe_rx_datak,
  input   [2:0] pipe_rx_status,
  input         pipe_rx_valid,
  input         pipe_phy_status,
  input         pipe_rx_elecidle,
  output        pipe_tx_clk,
  output [15:0] pipe_tx_data,
  output  [1:0] pipe_tx_datak,
  output        pipe_tx_elecidle,
  output        pipe_tx_compliance,
  output        pipe_tx_det_loopback,
  output        pipe_rx_polarity,
  output  [1:0] pipe_powerdown,
  output        pipe_reset_n
);
`ifdef USE_POWER_PINS
  `define PWR .vccd(vccd), .vssd(vssd), .vddio(vddio), .vssio(vssio), .vdda(vdda), .vssa(vssa),
`else
  `define PWR
`endif

  wire        c_clk, c_rst_n, c_uart_tx, c_uart_rx, c_spi_cs_n, c_spi_sclk, c_spi_mosi, c_spi_miso;
  wire        c_mclk, c_sdram_clk, c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_dq_oe;
  wire  [1:0] c_ba, c_dqm;
  wire [12:0] c_a;
  wire [15:0] c_gpio_in, c_gpio_out, c_gpio_oe, c_dq_in, c_dq_out;
  wire        c_rx_clk, c_rx_valid, c_phy_status, c_rx_ei, c_tx_clk, c_tx_ei, c_tx_comp, c_tx_det, c_rx_pol, c_phy_rst_n;
  wire [15:0] c_rx_data, c_tx_data;
  wire  [1:0] c_rx_datak, c_tx_datak, c_pd;
  wire  [2:0] c_rx_status;

  soc_top u_core (
    .clk(c_clk), .rst_n(c_rst_n), .uart_tx(c_uart_tx), .uart_rx(c_uart_rx),
    .gpio_in(c_gpio_in), .gpio_out(c_gpio_out), .gpio_oe(c_gpio_oe),
    .spi_cs_n(c_spi_cs_n), .spi_sclk(c_spi_sclk), .spi_mosi(c_spi_mosi), .spi_miso(c_spi_miso),
    .mclk(c_mclk), .sdram_clk(c_sdram_clk), .sdram_cke(c_cke), .sdram_cs_n(c_cs_n),
    .sdram_ras_n(c_ras_n), .sdram_cas_n(c_cas_n), .sdram_we_n(c_we_n),
    .sdram_ba(c_ba), .sdram_a(c_a), .sdram_dqm(c_dqm),
    .sdram_dq_out(c_dq_out), .sdram_dq_oe(c_dq_oe), .sdram_dq_in(c_dq_in),
    .pipe_rx_clk(c_rx_clk), .pipe_rx_data(c_rx_data), .pipe_rx_datak(c_rx_datak), .pipe_rx_status(c_rx_status),
    .pipe_rx_valid(c_rx_valid), .pipe_phy_status(c_phy_status), .pipe_rx_elecidle(c_rx_ei),
    .pipe_tx_clk(c_tx_clk), .pipe_tx_data(c_tx_data), .pipe_tx_datak(c_tx_datak), .pipe_tx_elecidle(c_tx_ei),
    .pipe_tx_compliance(c_tx_comp), .pipe_tx_det_loopback(c_tx_det), .pipe_rx_polarity(c_rx_pol),
    .pipe_powerdown(c_pd), .pipe_reset_n(c_phy_rst_n)
  );

  // inputs
  pad_gpio #(.DM(3'b001)) p_clk      (`PWR .pad(clk),      .a(1'b0), .oe(1'b0), .y(c_clk));
  pad_gpio #(.DM(3'b001)) p_rst_n    (`PWR .pad(rst_n),    .a(1'b0), .oe(1'b0), .y(c_rst_n));
  pad_gpio #(.DM(3'b001)) p_uart_rx  (`PWR .pad(uart_rx),  .a(1'b0), .oe(1'b0), .y(c_uart_rx));
  pad_gpio #(.DM(3'b001)) p_spi_miso (`PWR .pad(spi_miso), .a(1'b0), .oe(1'b0), .y(c_spi_miso));
  pad_gpio #(.DM(3'b001)) p_mclk     (`PWR .pad(mclk),     .a(1'b0), .oe(1'b0), .y(c_mclk));

  // outputs
  pad_gpio p_uart_tx     (`PWR .pad(uart_tx),      .a(c_uart_tx),   .oe(1'b1), .y());
  pad_gpio p_spi_cs_n    (`PWR .pad(spi_cs_n),     .a(c_spi_cs_n),  .oe(1'b1), .y());
  pad_gpio p_spi_sclk    (`PWR .pad(spi_sclk),     .a(c_spi_sclk),  .oe(1'b1), .y());
  pad_gpio p_spi_mosi    (`PWR .pad(spi_mosi),     .a(c_spi_mosi),  .oe(1'b1), .y());
  pad_gpio p_sdram_clk   (`PWR .pad(sdram_clk),    .a(c_sdram_clk), .oe(1'b1), .y());
  pad_gpio p_sdram_cke   (`PWR .pad(sdram_cke),    .a(c_cke),       .oe(1'b1), .y());
  pad_gpio p_sdram_cs_n  (`PWR .pad(sdram_cs_n),   .a(c_cs_n),      .oe(1'b1), .y());
  pad_gpio p_sdram_ras_n (`PWR .pad(sdram_ras_n),  .a(c_ras_n),     .oe(1'b1), .y());
  pad_gpio p_sdram_cas_n (`PWR .pad(sdram_cas_n),  .a(c_cas_n),     .oe(1'b1), .y());
  pad_gpio p_sdram_we_n  (`PWR .pad(sdram_we_n),   .a(c_we_n),      .oe(1'b1), .y());
  pad_gpio p_sdram_ba0   (`PWR .pad(sdram_ba[0]),  .a(c_ba[0]),     .oe(1'b1), .y());
  pad_gpio p_sdram_ba1   (`PWR .pad(sdram_ba[1]),  .a(c_ba[1]),     .oe(1'b1), .y());
  pad_gpio p_sdram_dqm0  (`PWR .pad(sdram_dqm[0]), .a(c_dqm[0]),    .oe(1'b1), .y());
  pad_gpio p_sdram_dqm1  (`PWR .pad(sdram_dqm[1]), .a(c_dqm[1]),    .oe(1'b1), .y());
  pad_gpio p_sdram_a0    (`PWR .pad(sdram_a[0]),   .a(c_a[0]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a1    (`PWR .pad(sdram_a[1]),   .a(c_a[1]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a2    (`PWR .pad(sdram_a[2]),   .a(c_a[2]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a3    (`PWR .pad(sdram_a[3]),   .a(c_a[3]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a4    (`PWR .pad(sdram_a[4]),   .a(c_a[4]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a5    (`PWR .pad(sdram_a[5]),   .a(c_a[5]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a6    (`PWR .pad(sdram_a[6]),   .a(c_a[6]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a7    (`PWR .pad(sdram_a[7]),   .a(c_a[7]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a8    (`PWR .pad(sdram_a[8]),   .a(c_a[8]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a9    (`PWR .pad(sdram_a[9]),   .a(c_a[9]),      .oe(1'b1), .y());
  pad_gpio p_sdram_a10   (`PWR .pad(sdram_a[10]),  .a(c_a[10]),     .oe(1'b1), .y());
  pad_gpio p_sdram_a11   (`PWR .pad(sdram_a[11]),  .a(c_a[11]),     .oe(1'b1), .y());
  pad_gpio p_sdram_a12   (`PWR .pad(sdram_a[12]),  .a(c_a[12]),     .oe(1'b1), .y());

  // bidirectional
  pad_gpio p_gpio0       (`PWR .pad(gpio[0]),      .a(c_gpio_out[0]),  .oe(c_gpio_oe[0]),  .y(c_gpio_in[0]));
  pad_gpio p_gpio1       (`PWR .pad(gpio[1]),      .a(c_gpio_out[1]),  .oe(c_gpio_oe[1]),  .y(c_gpio_in[1]));
  pad_gpio p_gpio2       (`PWR .pad(gpio[2]),      .a(c_gpio_out[2]),  .oe(c_gpio_oe[2]),  .y(c_gpio_in[2]));
  pad_gpio p_gpio3       (`PWR .pad(gpio[3]),      .a(c_gpio_out[3]),  .oe(c_gpio_oe[3]),  .y(c_gpio_in[3]));
  pad_gpio p_gpio4       (`PWR .pad(gpio[4]),      .a(c_gpio_out[4]),  .oe(c_gpio_oe[4]),  .y(c_gpio_in[4]));
  pad_gpio p_gpio5       (`PWR .pad(gpio[5]),      .a(c_gpio_out[5]),  .oe(c_gpio_oe[5]),  .y(c_gpio_in[5]));
  pad_gpio p_gpio6       (`PWR .pad(gpio[6]),      .a(c_gpio_out[6]),  .oe(c_gpio_oe[6]),  .y(c_gpio_in[6]));
  pad_gpio p_gpio7       (`PWR .pad(gpio[7]),      .a(c_gpio_out[7]),  .oe(c_gpio_oe[7]),  .y(c_gpio_in[7]));
  pad_gpio p_gpio8       (`PWR .pad(gpio[8]),      .a(c_gpio_out[8]),  .oe(c_gpio_oe[8]),  .y(c_gpio_in[8]));
  pad_gpio p_gpio9       (`PWR .pad(gpio[9]),      .a(c_gpio_out[9]),  .oe(c_gpio_oe[9]),  .y(c_gpio_in[9]));
  pad_gpio p_gpio10      (`PWR .pad(gpio[10]),     .a(c_gpio_out[10]), .oe(c_gpio_oe[10]), .y(c_gpio_in[10]));
  pad_gpio p_gpio11      (`PWR .pad(gpio[11]),     .a(c_gpio_out[11]), .oe(c_gpio_oe[11]), .y(c_gpio_in[11]));
  pad_gpio p_gpio12      (`PWR .pad(gpio[12]),     .a(c_gpio_out[12]), .oe(c_gpio_oe[12]), .y(c_gpio_in[12]));
  pad_gpio p_gpio13      (`PWR .pad(gpio[13]),     .a(c_gpio_out[13]), .oe(c_gpio_oe[13]), .y(c_gpio_in[13]));
  pad_gpio p_gpio14      (`PWR .pad(gpio[14]),     .a(c_gpio_out[14]), .oe(c_gpio_oe[14]), .y(c_gpio_in[14]));
  pad_gpio p_gpio15      (`PWR .pad(gpio[15]),     .a(c_gpio_out[15]), .oe(c_gpio_oe[15]), .y(c_gpio_in[15]));
  pad_gpio p_sdram_dq0   (`PWR .pad(sdram_dq[0]),  .a(c_dq_out[0]),    .oe(c_dq_oe),       .y(c_dq_in[0]));
  pad_gpio p_sdram_dq1   (`PWR .pad(sdram_dq[1]),  .a(c_dq_out[1]),    .oe(c_dq_oe),       .y(c_dq_in[1]));
  pad_gpio p_sdram_dq2   (`PWR .pad(sdram_dq[2]),  .a(c_dq_out[2]),    .oe(c_dq_oe),       .y(c_dq_in[2]));
  pad_gpio p_sdram_dq3   (`PWR .pad(sdram_dq[3]),  .a(c_dq_out[3]),    .oe(c_dq_oe),       .y(c_dq_in[3]));
  pad_gpio p_sdram_dq4   (`PWR .pad(sdram_dq[4]),  .a(c_dq_out[4]),    .oe(c_dq_oe),       .y(c_dq_in[4]));
  pad_gpio p_sdram_dq5   (`PWR .pad(sdram_dq[5]),  .a(c_dq_out[5]),    .oe(c_dq_oe),       .y(c_dq_in[5]));
  pad_gpio p_sdram_dq6   (`PWR .pad(sdram_dq[6]),  .a(c_dq_out[6]),    .oe(c_dq_oe),       .y(c_dq_in[6]));
  pad_gpio p_sdram_dq7   (`PWR .pad(sdram_dq[7]),  .a(c_dq_out[7]),    .oe(c_dq_oe),       .y(c_dq_in[7]));
  pad_gpio p_sdram_dq8   (`PWR .pad(sdram_dq[8]),  .a(c_dq_out[8]),    .oe(c_dq_oe),       .y(c_dq_in[8]));
  pad_gpio p_sdram_dq9   (`PWR .pad(sdram_dq[9]),  .a(c_dq_out[9]),    .oe(c_dq_oe),       .y(c_dq_in[9]));
  pad_gpio p_sdram_dq10  (`PWR .pad(sdram_dq[10]), .a(c_dq_out[10]),   .oe(c_dq_oe),       .y(c_dq_in[10]));
  pad_gpio p_sdram_dq11  (`PWR .pad(sdram_dq[11]), .a(c_dq_out[11]),   .oe(c_dq_oe),       .y(c_dq_in[11]));
  pad_gpio p_sdram_dq12  (`PWR .pad(sdram_dq[12]), .a(c_dq_out[12]),   .oe(c_dq_oe),       .y(c_dq_in[12]));
  pad_gpio p_sdram_dq13  (`PWR .pad(sdram_dq[13]), .a(c_dq_out[13]),   .oe(c_dq_oe),       .y(c_dq_in[13]));
  pad_gpio p_sdram_dq14  (`PWR .pad(sdram_dq[14]), .a(c_dq_out[14]),   .oe(c_dq_oe),       .y(c_dq_in[14]));
  pad_gpio p_sdram_dq15  (`PWR .pad(sdram_dq[15]), .a(c_dq_out[15]),   .oe(c_dq_oe),       .y(c_dq_in[15]));

  // PCIe PHY inputs, 1.8 V levels
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_clk          (`PWR .pad(pipe_rx_clk),          .a(1'b0), .oe(1'b0), .y(c_rx_clk));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data0        (`PWR .pad(pipe_rx_data[0]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[0]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data1        (`PWR .pad(pipe_rx_data[1]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[1]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data2        (`PWR .pad(pipe_rx_data[2]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[2]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data3        (`PWR .pad(pipe_rx_data[3]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[3]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data4        (`PWR .pad(pipe_rx_data[4]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[4]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data5        (`PWR .pad(pipe_rx_data[5]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[5]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data6        (`PWR .pad(pipe_rx_data[6]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[6]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data7        (`PWR .pad(pipe_rx_data[7]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[7]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data8        (`PWR .pad(pipe_rx_data[8]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[8]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data9        (`PWR .pad(pipe_rx_data[9]),      .a(1'b0), .oe(1'b0), .y(c_rx_data[9]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data10       (`PWR .pad(pipe_rx_data[10]),     .a(1'b0), .oe(1'b0), .y(c_rx_data[10]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data11       (`PWR .pad(pipe_rx_data[11]),     .a(1'b0), .oe(1'b0), .y(c_rx_data[11]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data12       (`PWR .pad(pipe_rx_data[12]),     .a(1'b0), .oe(1'b0), .y(c_rx_data[12]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data13       (`PWR .pad(pipe_rx_data[13]),     .a(1'b0), .oe(1'b0), .y(c_rx_data[13]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data14       (`PWR .pad(pipe_rx_data[14]),     .a(1'b0), .oe(1'b0), .y(c_rx_data[14]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_data15       (`PWR .pad(pipe_rx_data[15]),     .a(1'b0), .oe(1'b0), .y(c_rx_data[15]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_datak0       (`PWR .pad(pipe_rx_datak[0]),     .a(1'b0), .oe(1'b0), .y(c_rx_datak[0]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_datak1       (`PWR .pad(pipe_rx_datak[1]),     .a(1'b0), .oe(1'b0), .y(c_rx_datak[1]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_status0      (`PWR .pad(pipe_rx_status[0]),    .a(1'b0), .oe(1'b0), .y(c_rx_status[0]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_status1      (`PWR .pad(pipe_rx_status[1]),    .a(1'b0), .oe(1'b0), .y(c_rx_status[1]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_status2      (`PWR .pad(pipe_rx_status[2]),    .a(1'b0), .oe(1'b0), .y(c_rx_status[2]));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_valid        (`PWR .pad(pipe_rx_valid),        .a(1'b0), .oe(1'b0), .y(c_rx_valid));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_phy_status      (`PWR .pad(pipe_phy_status),      .a(1'b0), .oe(1'b0), .y(c_phy_status));
  pad_gpio #(.DM(3'b001), .IB(1'b1)) p_pipe_rx_elecidle     (`PWR .pad(pipe_rx_elecidle),     .a(1'b0), .oe(1'b0), .y(c_rx_ei));

  // PCIe PHY outputs
  pad_gpio p_pipe_tx_clk          (`PWR .pad(pipe_tx_clk),          .a(c_tx_clk), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data0        (`PWR .pad(pipe_tx_data[0]),      .a(c_tx_data[0]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data1        (`PWR .pad(pipe_tx_data[1]),      .a(c_tx_data[1]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data2        (`PWR .pad(pipe_tx_data[2]),      .a(c_tx_data[2]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data3        (`PWR .pad(pipe_tx_data[3]),      .a(c_tx_data[3]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data4        (`PWR .pad(pipe_tx_data[4]),      .a(c_tx_data[4]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data5        (`PWR .pad(pipe_tx_data[5]),      .a(c_tx_data[5]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data6        (`PWR .pad(pipe_tx_data[6]),      .a(c_tx_data[6]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data7        (`PWR .pad(pipe_tx_data[7]),      .a(c_tx_data[7]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data8        (`PWR .pad(pipe_tx_data[8]),      .a(c_tx_data[8]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data9        (`PWR .pad(pipe_tx_data[9]),      .a(c_tx_data[9]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data10       (`PWR .pad(pipe_tx_data[10]),     .a(c_tx_data[10]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data11       (`PWR .pad(pipe_tx_data[11]),     .a(c_tx_data[11]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data12       (`PWR .pad(pipe_tx_data[12]),     .a(c_tx_data[12]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data13       (`PWR .pad(pipe_tx_data[13]),     .a(c_tx_data[13]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data14       (`PWR .pad(pipe_tx_data[14]),     .a(c_tx_data[14]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_data15       (`PWR .pad(pipe_tx_data[15]),     .a(c_tx_data[15]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_datak0       (`PWR .pad(pipe_tx_datak[0]),     .a(c_tx_datak[0]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_datak1       (`PWR .pad(pipe_tx_datak[1]),     .a(c_tx_datak[1]), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_elecidle     (`PWR .pad(pipe_tx_elecidle),     .a(c_tx_ei), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_compliance   (`PWR .pad(pipe_tx_compliance),   .a(c_tx_comp), .oe(1'b1), .y());
  pad_gpio p_pipe_tx_det_loopback (`PWR .pad(pipe_tx_det_loopback), .a(c_tx_det), .oe(1'b1), .y());
  pad_gpio p_pipe_rx_polarity     (`PWR .pad(pipe_rx_polarity),     .a(c_rx_pol), .oe(1'b1), .y());
  pad_gpio p_pipe_powerdown0      (`PWR .pad(pipe_powerdown[0]),    .a(c_pd[0]), .oe(1'b1), .y());
  pad_gpio p_pipe_powerdown1      (`PWR .pad(pipe_powerdown[1]),    .a(c_pd[1]), .oe(1'b1), .y());
  pad_gpio p_pipe_reset_n         (`PWR .pad(pipe_reset_n),         .a(c_phy_rst_n), .oe(1'b1), .y());
endmodule

// gpiov2 pad: push-pull output (DM 110) or input only (DM 001), fast slew. Inputs use CMOS levels on VDDIO,
// or with IB the 1.8 V input buffer on VCCHIB.
// The pad's own tie cells hold HLD_H_N, ENABLE_H and ENABLE_VDDA_H high, ENABLE_INP_H and ENABLE_VSWITCH_H low.
module pad_gpio #(parameter [2:0] DM = 3'b110, parameter IB = 1'b0) (
`ifdef USE_POWER_PINS
  inout  vccd, vssd, vddio, vssio, vdda, vssa,
`endif
  inout  pad,
  input  a,
  input  oe,
  output y
);
  wire hi, lo;
  sky130_ef_io__gpiov2_pad_wrapped p (
`ifdef USE_POWER_PINS
    .VCCD(vccd), .VCCHIB(vccd), .VSSD(vssd), .VDDIO(vddio), .VDDIO_Q(vddio), .VSWITCH(vddio),
    .VSSIO(vssio), .VSSIO_Q(vssio), .VDDA(vdda), .VSSA(vssa),
`endif
    .PAD(pad), .OUT(a), .OE_N(!oe), .IN(y), .DM(DM),
    .INP_DIS(1'b0), .IB_MODE_SEL(IB), .VTRIP_SEL(1'b0), .SLOW(1'b0), .HLD_OVR(1'b0),
    .ANALOG_EN(1'b0), .ANALOG_SEL(1'b0), .ANALOG_POL(1'b0), .ENABLE_VDDIO(1'b1),
    .TIE_HI_ESD(hi), .TIE_LO_ESD(lo), .HLD_H_N(hi), .ENABLE_H(hi), .ENABLE_VDDA_H(hi),
    .ENABLE_INP_H(lo), .ENABLE_VSWITCH_H(lo),
    .IN_H(), .PAD_A_NOESD_H(), .PAD_A_ESD_0_H(), .PAD_A_ESD_1_H(), .AMUXBUS_A(), .AMUXBUS_B()
  );
endmodule
