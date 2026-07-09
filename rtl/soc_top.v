// SoC top: RV32I core, boot loader, AXI4-Lite interconnect, 2 KB SRAM, APB peripherals.
// Map: 0x0000_0000 SRAM, 0x1000_0000 UART, 0x1000_1000 GPIO, 0x1000_2000 SPI,
//      0x1000_3000 TIMER, 0x1000_4000 INTC.
module soc_top (
  input         clk,
  input         rst_n,
  output        uart_tx,
  input         uart_rx,
  input  [15:0] gpio_in,
  output [15:0] gpio_out,
  output [15:0] gpio_oe,
  output        spi_cs_n,
  output        spi_sclk,
  output        spi_mosi,
  input         spi_miso
);
  reg [1:0] rs;
  always @(posedge clk) rs <= {rs[0], rst_n};
  wire rst = !rs[1];

  // ---------------- masters ----------------
  wire        boot_done;
  wire [31:0] i_addr, i_rdata;

  wire [31:0] c_awaddr, c_wdata, c_araddr, b_awaddr, b_wdata;
  wire  [3:0] c_wstrb;
  wire        c_awvalid, c_wvalid, c_bready, c_arvalid, c_rready, b_awvalid, b_wvalid, b_bready;
  wire  [1:0] m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
  wire [31:0] m_rdata;
  wire        irq_timer, irq_ext;

  rv32i u_cpu (
    .clk(clk), .rst(rst || !boot_done),
    .i_addr(i_addr), .i_rdata(i_rdata),
    .m_awaddr(c_awaddr), .m_awvalid(c_awvalid), .m_awready(m_awready[0]),
    .m_wdata(c_wdata), .m_wstrb(c_wstrb), .m_wvalid(c_wvalid), .m_wready(m_wready[0]),
    .m_bvalid(m_bvalid[0]), .m_bready(c_bready),
    .m_araddr(c_araddr), .m_arvalid(c_arvalid), .m_arready(m_arready[0]),
    .m_rdata(m_rdata), .m_rvalid(m_rvalid[0]), .m_rready(c_rready),
    .irq_timer(irq_timer), .irq_ext(irq_ext)
  );

  wire b_cs_n, b_sclk, b_mosi;
  boot u_boot (
    .clk(clk), .rst(rst), .done(boot_done),
    .awaddr(b_awaddr), .awvalid(b_awvalid), .awready(m_awready[1]),
    .wdata(b_wdata), .wvalid(b_wvalid), .wready(m_wready[1]),
    .bvalid(m_bvalid[1]), .bready(b_bready),
    .cs_n(b_cs_n), .sclk(b_sclk), .mosi(b_mosi), .miso(spi_miso)
  );

  // ---------------- interconnect ----------------
  wire [31:0] s_awaddr, s_wdata, s_araddr;
  wire  [3:0] s_wstrb;
  wire  [1:0] s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
  wire  [1:0] s_arvalid, s_arready, s_rvalid, s_rready;
  wire [31:0] s0_rdata, s1_rdata;

  axil_ic u_ic (
    .clk(clk), .rst(rst),
    .m_awaddr({b_awaddr, c_awaddr}), .m_awvalid({b_awvalid, c_awvalid}), .m_awready(m_awready),
    .m_wdata({b_wdata, c_wdata}), .m_wstrb({4'hf, c_wstrb}), .m_wvalid({b_wvalid, c_wvalid}),
    .m_wready(m_wready), .m_bvalid(m_bvalid), .m_bready({b_bready, c_bready}),
    .m_araddr({32'b0, c_araddr}), .m_arvalid({1'b0, c_arvalid}), .m_arready(m_arready),
    .m_rdata(m_rdata), .m_rvalid(m_rvalid), .m_rready({1'b1, c_rready}),
    .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bvalid(s_bvalid), .s_bready(s_bready),
    .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rdata({s1_rdata, s0_rdata}), .s_rvalid(s_rvalid), .s_rready(s_rready)
  );

  sram_axil u_sram (
    .clk(clk), .rst(rst),
    .awaddr(s_awaddr), .awvalid(s_awvalid[0]), .awready(s_awready[0]),
    .wdata(s_wdata), .wstrb(s_wstrb), .wvalid(s_wvalid[0]), .wready(s_wready[0]),
    .bvalid(s_bvalid[0]), .bready(s_bready[0]),
    .araddr(s_araddr), .arvalid(s_arvalid[0]), .arready(s_arready[0]),
    .rdata(s0_rdata), .rvalid(s_rvalid[0]), .rready(s_rready[0]),
    .i_addr(i_addr), .i_rdata(i_rdata)
  );

  // ---------------- peripherals ----------------
  wire [31:0] paddr, pwdata;
  wire        pwrite, penable;
  wire  [4:0] psel;
  wire [31:0] rd_uart, rd_gpio, rd_spi, rd_timer, rd_intc;

  axil2apb u_apb (
    .clk(clk), .rst(rst),
    .awaddr(s_awaddr), .awvalid(s_awvalid[1]), .awready(s_awready[1]),
    .wdata(s_wdata), .wvalid(s_wvalid[1]), .wready(s_wready[1]),
    .bvalid(s_bvalid[1]), .bready(s_bready[1]),
    .araddr(s_araddr), .arvalid(s_arvalid[1]), .arready(s_arready[1]),
    .rdata(s1_rdata), .rvalid(s_rvalid[1]), .rready(s_rready[1]),
    .paddr(paddr), .pwrite(pwrite), .pwdata(pwdata), .psel(psel), .penable(penable),
    .prdata({rd_intc, rd_timer, rd_spi, rd_gpio, rd_uart})
  );

  wire irq_uart, irq_spi;
  wire s_cs_n, s_sclk, s_mosi;

  uart u_uart (
    .clk(clk), .rst(rst), .psel(psel[0]), .penable(penable), .pwrite(pwrite),
    .paddr(paddr[3:2]), .pwdata(pwdata), .prdata(rd_uart),
    .tx(uart_tx), .rx(uart_rx), .irq(irq_uart)
  );

  gpio u_gpio (
    .clk(clk), .rst(rst), .psel(psel[1]), .penable(penable), .pwrite(pwrite),
    .paddr(paddr[3:2]), .pwdata(pwdata), .prdata(rd_gpio),
    .gpio_in(gpio_in), .gpio_out(gpio_out), .gpio_oe(gpio_oe)
  );

  spi u_spi (
    .clk(clk), .rst(rst), .psel(psel[2]), .penable(penable), .pwrite(pwrite),
    .paddr(paddr[3:2]), .pwdata(pwdata), .prdata(rd_spi),
    .cs_n(s_cs_n), .sclk(s_sclk), .mosi(s_mosi), .miso(spi_miso), .irq(irq_spi)
  );

  timer u_timer (
    .clk(clk), .rst(rst), .psel(psel[3]), .penable(penable), .pwrite(pwrite),
    .paddr(paddr[3:2]), .pwdata(pwdata), .prdata(rd_timer), .irq(irq_timer)
  );

  intc u_intc (
    .clk(clk), .rst(rst), .psel(psel[4]), .penable(penable), .pwrite(pwrite),
    .paddr(paddr[3:2]), .pwdata(pwdata), .prdata(rd_intc),
    .src({irq_spi, irq_uart}), .irq(irq_ext)
  );

  // flash pins belong to the boot loader until boot is done
  assign spi_cs_n = boot_done ? s_cs_n : b_cs_n;
  assign spi_sclk = boot_done ? s_sclk : b_sclk;
  assign spi_mosi = boot_done ? s_mosi : b_mosi;
endmodule
