`timescale 1ns/1ps
// The endpoint's side of the PCIe lane. Transmit: the endpoint's symbols in 8b/10b, ten bits per symbol clock of the
// endpoint (250 ppm off the reference by default), each bit placed from that clock's edge. Receive: bits recovered
// from the line's edges, aligned on COM and decoded into symbol strobes. Pull-downs on the root's transmit pair stand
// for the receiver termination that the root's PHY detects.
// Plusargs: +phy_swap (P and N swapped on the endpoint's transmit pair), +phy_dec_err=N (an invalid code in place of
// the Nth data symbol of the endpoint's packets).
module pcie_lane (
  input      [7:0] tx_sym,
  input            tx_k,
  input            tx_idle,
  input            tx_stb,
  output reg [7:0] rx_sym,
  output reg       rx_k,
  output reg       rx_idle,
  output reg       rx_stb,
  output           rxp,              // the root's receive pair
  output           rxn,
  inout            txp,              // the root's transmit pair
  inout            txn
);
  `include "b8b10.vh"
  localparam real UI = 0.4;
  pulldown (txp);
  pulldown (txn);

  initial begin rx_sym = 0; rx_k = 0; rx_idle = 1; rx_stb = 0; end

  // ---------------- transmit ----------------
  reg      lp = 0, ln = 0, rd = 0, swap = 0, in_pkt = 0;
  integer  dec_err_at = 0, dsym = 0;
  realtime t_stb = 0, uid = UI;
  assign rxp = swap ? ln : lp;
  assign rxn = swap ? lp : ln;
  initial begin
    swap = $test$plusargs("phy_swap");
    if (!$value$plusargs("phy_dec_err=%d", dec_err_at)) dec_err_at = 0;
  end

  // the endpoint changes its symbol on the falling edge
  always @(posedge tx_stb) begin : tx
    reg [10:0] e;
    reg  [9:0] c;
    integer    b;
    if (t_stb > 0) uid = ($realtime - t_stb) / 10.0;
    t_stb = $realtime;
    if (tx_idle) begin
      lp <= 1'b0; ln <= 1'b0;
    end else begin
      e = enc(tx_k, tx_sym, rd);
      rd = e[10];
      c = e[9:0];
      if (!tx_k && in_pkt) begin
        dsym = dsym + 1;
        if (dsym == dec_err_at) c = 10'b0000000000;
      end
      if (tx_k && (tx_sym == STP || tx_sym == SDP)) in_pkt = 1;
      if (tx_k && (tx_sym == END || tx_sym == EDB)) in_pkt = 0;
      for (b = 0; b < 10; b = b + 1) begin
        lp <= #(b * uid) c[9 - b];
        ln <= #(b * uid) !c[9 - b];
      end
    end
  end

  // ---------------- receive ----------------
  reg        line_idle = 1, eq = 1, lvl = 0, aligned = 0;
  realtime   t_prev = 0, t_eq = 0;
  reg  [9:0] sh = 0;
  integer    nb = 0;

  always @(txp or txn)
    if (txp === txn || txp === 1'bz || txp === 1'bx) begin
      if (!eq) begin eq = 1; t_eq = $realtime; end
    end else begin
      eq = 0;
      if (line_idle) begin line_idle = 0; t_prev = $realtime; lvl = txp; rx_idle <= #0.2 1'b0; end
    end
  always @(txp) if (!line_idle && (txp === 1'b0 || txp === 1'b1) && txp !== lvl) begin
    run($realtime);
    lvl = txp;
  end
  always @(posedge eq) begin
    #(2.0 * UI);
    if (eq && !line_idle) begin
      run(t_eq);
      line_idle = 1; aligned = 0;
      // after the strobe of the last symbol
      rx_idle <= #2.5 1'b1;
    end
  end

  task run(input realtime t);
    integer n;
    begin
      n = $rtoi((t - t_prev) / UI + 0.5);
      repeat (n) bit_in(lvl);
      t_prev = t;
    end
  endtask

  task bit_in(input b);
    begin
      sh = {sh[8:0], b};
      nb = nb + 1;
      if (sh == COM_N || sh == COM_P) begin
        aligned = 1; nb = 0; symbol(sh);
      end else if (aligned && nb == 10) begin
        nb = 0; symbol(sh);
      end
    end
  endtask

  task symbol(input [9:0] c);
    reg [9:0] d;
    begin
      d = dtab[c];
      if (!d[9]) d = {1'b0, 1'b1, EDB};
      rx_sym <= #0.5 d[7:0];
      rx_k <= #0.5 d[8];
      rx_stb <= #1.0 1'b1;
      rx_stb <= #2.0 1'b0;
    end
  endtask
endmodule
