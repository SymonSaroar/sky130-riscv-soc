// UART 8N1. Regs: 0x0 DATA (wr: send, rd: receive), 0x4 STATUS {rx_valid, tx_busy}, 0x8 DIV (clocks per bit).
module uart (
  input             clk,
  input             rst,
  input             psel,
  input             penable,
  input             pwrite,
  input       [3:2] paddr,
  input      [31:0] pwdata,
  output reg [31:0] prdata,
  output            tx,
  input             rx,
  output            irq
);
  reg [15:0] div;
  wire wr = psel && penable && pwrite;
  wire rd = psel && penable && !pwrite;

  // transmitter
  reg  [9:0] tsh;
  reg  [3:0] tbits;
  reg [15:0] tcnt;
  wire tx_busy = tbits != 0;
  assign tx = tx_busy ? tsh[0] : 1'b1;

  // receiver
  reg  [1:0] rs;
  reg  [9:0] rsh;
  reg  [3:0] rbits;
  reg [15:0] rcnt;
  reg  [7:0] rx_data;
  reg        rx_valid;
  assign irq = rx_valid;

  always @* case (paddr)
    2'd0:    prdata = {24'b0, rx_data};
    2'd1:    prdata = {30'b0, rx_valid, tx_busy};
    default: prdata = {16'b0, div};
  endcase

  always @(posedge clk) begin
    if (rst) begin
      div      <= 16'd434;
      tbits    <= 4'd0;
      rbits    <= 4'd0;
      rx_valid <= 1'b0;
      rs       <= 2'b11;
    end else begin
      if (wr && paddr == 2'd2) div <= pwdata[15:0];

      if (wr && paddr == 2'd0 && !tx_busy) begin
        tsh   <= {1'b1, pwdata[7:0], 1'b0};
        tbits <= 4'd10;
        tcnt  <= div - 1;
      end else if (tx_busy) begin
        if (tcnt == 0) begin
          tsh   <= {1'b1, tsh[9:1]};
          tbits <= tbits - 1;
          tcnt  <= div - 1;
        end else tcnt <= tcnt - 1;
      end

      rs <= {rs[0], rx};
      if (rd && paddr == 2'd0) rx_valid <= 1'b0;
      if (rbits == 0) begin
        if (!rs[1]) begin
          rbits <= 4'd10;
          rcnt  <= div >> 1;
        end
      end else if (rcnt == 0) begin
        rsh   <= {rs[1], rsh[9:1]};
        rbits <= rbits - 1;
        rcnt  <= div - 1;
        if (rbits == 1) begin
          rx_data  <= rsh[9:2];
          rx_valid <= 1'b1;
        end
      end else rcnt <= rcnt - 1;
    end
  end
endmodule
