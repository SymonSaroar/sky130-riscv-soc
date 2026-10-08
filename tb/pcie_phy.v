`timescale 1ns/1ps
// Model of the PCIe PHY macro: PIPE 32-bit, x1 Gen1, PCLK as a PHY input. MaxPCLK and the 2.5 Gb/s bit time come
// from the 100 MHz reference clock. PIPE inputs are sampled on PCLK rising; outputs change T_CQ after it.
// Transmit: four symbols per clock in 8b/10b, serialized a bit at a time from bit 9; electrical idle drives both
// lines low. Receive: bits recovered from the line's edges, aligned on COM, decoded, inverted while RxPolarity is
// set, and passed through an elastic buffer that adds or removes one SKP per SKP ordered set. Receiver detection in
// P1 releases the transmit lines and reads the link partner's termination.
// Violations of the MAC rules count in `errors`; the PIPE setup and hold checks run in gate-level simulation.
`ifndef PHY_K
`define PHY_K 1
`endif
module pcie_phy (
`ifdef USE_POWER_PINS
  inout             vccd, vssd, avdd, avss,
`endif
  input             pclk,
  output reg        max_pclk,
  input             reset_n,
  input      [31:0] tx_data,
  input       [3:0] tx_datak,
  input             tx_elecidle,
  input             tx_compliance,
  input             tx_detectrx_loopback,
  input             rx_polarity,
  input       [1:0] powerdown,
  output reg [31:0] rx_data,
  output reg  [3:0] rx_datak,
  output reg        rx_valid,
  output reg  [2:0] rx_status,
  output reg        rx_elecidle,
  output reg        phy_status,
  inout             txp,
  inout             txn,
  input             rxp,
  input             rxn,
  input             refclk_p,
  input             refclk_n,
  inout             rext
);
  `include "b8b10.vh"
  localparam real K = `PHY_K;
  localparam real T_SETUP = K > 1.0 ? 1.0 * K : 1.0, T_HOLD = 0.5, T_CQ = 1.5 * K;
  localparam [1:0] P0 = 2'b00, P1 = 2'b10;
  integer errors = 0;
  // PHY state, elastic buffer state
  reg  [1:0] pstate = P1;
  reg        ready = 0, locked = 0, started = 0, os_adj = 0, after_com = 0, in_pkt = 0;
  integer    wp = 0, rp = 0, com_i = 0, coms = 0;

  task violation(input [8*64-1:0] what);
    begin errors = errors + 1; $display("PHY VIOLATION at %0t ns: %0s", $time, what); end
  endtask

  initial begin
    max_pclk = 0; rx_data = 0; rx_datak = 0; rx_valid = 0; rx_status = 0; rx_elecidle = 1; phy_status = 1;
  end

  // ---------------- clocks: 25 bits per reference period, 40 bits per MaxPCLK period ----------------
  realtime t_ref = 0, ui = 0.4;
  always @(posedge refclk_p) begin
    if (t_ref > 0) ui = ($realtime - t_ref) / 25.0;
    t_ref = $realtime;
  end
  always begin
    wait (t_ref > 0);
    #(20.0 * ui) max_pclk = !max_pclk;
  end
  initial #1000 if (rext !== 1'b0) violation("REXT not connected to its resistor");

  // ---------------- transmit: symbols queued on PCLK, one bit per UI ----------------
  reg  [9:0] tq [0:63];
  integer    tw = 0, tr = 0;
  reg        trd = 0, lp = 0, ln = 0, drv = 1;
  assign txp = drv ? lp : 1'bz;
  assign txn = drv ? ln : 1'bz;
  always begin : ser
    reg [9:0] c;
    integer   b;
    wait (t_ref > 0);
    // two words queued before the line leaves electrical idle, so the next word is in before the queue runs dry
    if (tw - tr >= 8 || (tw > tr && lp != ln)) begin
      c = tq[tr % 64];
      tr = tr + 1;
      for (b = 9; b >= 0; b = b - 1) begin lp = c[b]; ln = !c[b]; #(ui); end
    end else begin
      lp = 0; ln = 0; #(ui);
    end
  end

  // ---------------- receive: bits from the line's edges ----------------
  reg        line_idle = 1, eq = 1, lvl = 0, aligned = 0, pol_on = 0;
  realtime   t_prev = 0, t_eq = 0;
  reg  [9:0] sh = 0;
  integer    nb = 0;

  always @(rxp or rxn)
    if (rxp === rxn) begin
      if (!eq) begin eq = 1; t_eq = $realtime; end
    end else begin
      eq = 0;
      if (line_idle) begin line_idle = 0; t_prev = $realtime; lvl = rxp; end
    end
  always @(rxp) if (!line_idle && (rxp === 1'b0 || rxp === 1'b1) && rxp !== lvl) begin
    run($realtime);
    lvl = rxp;
  end
  // squelch: the lines equal for two bit times
  always @(posedge eq) begin
    #(2.0 * ui);
    if (eq && !line_idle) begin
      run(t_eq);
      line_idle = 1; aligned = 0; locked = 0; started = 0; coms = 0; wp = 0; rp = 0; in_pkt = 0;
    end
  end

  task run(input realtime t);
    integer n;
    begin
      n = $rtoi((t - t_prev) / ui + 0.5);
      repeat (n) bit_in(lvl);
      t_prev = t;
    end
  endtask

  task bit_in(input b);
    begin
      sh = {sh[8:0], b ^ pol_on};
      nb = nb + 1;
      if (sh == COM_N || sh == COM_P) begin
        aligned = 1; nb = 0; symbol(sh);
      end else if (aligned && nb == 10) begin
        nb = 0; symbol(sh);
      end
    end
  endtask

  // ---------------- elastic buffer ----------------
  reg  [7:0] eb_sym [0:63];
  reg        eb_k [0:63];
  reg  [2:0] eb_st [0:63];

  task push(input [7:0] s, input k, input [2:0] st);
    begin eb_sym[wp % 64] = s; eb_k[wp % 64] = k; eb_st[wp % 64] = st; wp = wp + 1; end
  endtask

  task symbol(input [9:0] c);
    reg [9:0] d;
    reg [2:0] st;
    begin
      d = dtab[c];
      st = d[9] ? 3'b000 : 3'b100;
      if (!d[9]) d = {1'b0, 1'b1, EDB};
      if (d[8] && (d[7:0] == STP || d[7:0] == SDP)) in_pkt = 1;
      if (d[8] && (d[7:0] == END || d[7:0] == EDB)) in_pkt = 0;
      if (!locked) begin
        if (d[8] && d[7:0] == COM) coms = coms + 1;
        if (coms >= 2) begin locked = 1; started = 0; wp = 0; rp = 0; end
      end
      if (locked && ready && pstate != P1) begin
        if (d[8] && d[7:0] == COM) begin
          com_i = wp; after_com = 1; os_adj = 0; push(d[7:0], 1'b1, st);
        end else if (after_com && d[8] && d[7:0] == SKP && !os_adj && started && wp - rp > 14) begin
          eb_st[com_i % 64] = 3'b010; os_adj = 1;                // one SKP removed
        end else if (after_com && d[8] && d[7:0] == SKP && !os_adj && started && wp - rp < 6) begin
          eb_st[com_i % 64] = 3'b001; os_adj = 1;                // one SKP added
          push(SKP, 1'b1, 3'b000); push(SKP, 1'b1, 3'b000);
        end else begin
          if (!(d[8] && d[7:0] == SKP)) after_com = 0;
          push(d[7:0], d[8], st);
        end
        if (wp - rp > 60) begin violation("elastic buffer overflow"); rp = wp - 10; end
      end
    end
  endtask

  // ---------------- MAC side ----------------
  integer    rcnt = 0, pcnt = 0, dcnt = 0, dhold = 0, polcnt = 0;
  reg  [7:0] last [0:3];
  reg        ei_q = 1;

  always @(posedge pclk) begin : mac
    reg        ps, v, go;
    reg  [2:0] st, t;
    reg [31:0] d;
    reg  [3:0] k;
    reg [10:0] e;
    integer    i;
    ps = 0; st = 3'b000; v = 0; d = 0; k = 0;
    if (!reset_n) begin
      ready = 0; rcnt = 0; pstate = P1; ps = 1; pcnt = 0; dcnt = 0; dhold = 0; tw = 0; tr = 0; pol_on = 0; ei_q = 1;
      if (tx_detectrx_loopback === 1'b1 || tx_elecidle === 1'b0 || tx_compliance === 1'b1 ||
          rx_polarity === 1'b1 || powerdown === P0) violation("PIPE inputs not at their reset values during reset");
    end else if (!ready) begin
      rcnt = rcnt + 1; ps = 1;
      if (rcnt == 2) begin ready = 1; ps = 0; pstate = powerdown; end
    end else begin
      // power state changes end with PhyStatus for one clock
      if (pcnt != 0) begin
        pcnt = pcnt - 1;
        if (pcnt == 0) begin pstate = powerdown; ps = 1; end
      end else if (powerdown != pstate) pcnt = 4;
      // receiver detection in P1: the lines released for the last 10 clocks
      if (dcnt != 0) begin
        dcnt = dcnt - 1;
        if (dcnt == 10) drv = 0;
        if (dcnt == 0) begin
          ps = 1; st = txp === 1'b0 && txn === 1'b0 ? 3'b011 : 3'b000; drv = 1; dhold = 1;
        end
      end else if (dhold != 0) begin
        if (!tx_detectrx_loopback) dhold = 0;
        else if (dhold > 32) begin violation("TxDetectRx held after the detection completed"); dhold = 0; end
        else dhold = dhold + 1;
      end else if (pstate == P1 && tx_detectrx_loopback) dcnt = 50;
      if (pstate != P1 && tx_detectrx_loopback && !tx_elecidle) violation("loopback requested");
      // RxPolarity takes effect within 10 clocks
      if (rx_polarity != pol_on) begin
        polcnt = polcnt + 1;
        if (polcnt == 6) begin pol_on = rx_polarity; polcnt = 0; end
      end else polcnt = 0;
      // four symbols out of the elastic buffer
      if (locked && pstate != P1) begin
        if (!started && wp - rp >= 10) started = 1;
        if (started) begin
          v = 1;
          if (wp - rp < 4) begin
            d = {4{EDB}}; k = 4'b1111; st = 3'b110;
          end else begin
            for (i = 0; i < 4; i = i + 1) begin
              d[i * 8 +: 8] = eb_sym[(rp + i) % 64]; k[i] = eb_k[(rp + i) % 64]; t = eb_st[(rp + i) % 64];
              if (t == 3'b100 || st == 3'b100) st = 3'b100;
              else if (!st[2] && (t[2] || st == 3'b000)) st = t;
            end
            rp = rp + 4;
          end
        end
      end
      // transmit: four symbols into the serializer queue
      go = pstate == P0 && !tx_elecidle;
      if (pstate == P0 && tx_elecidle && !ei_q &&
          !(last[0] == COM && last[1] == IDL && last[2] == IDL && last[3] == IDL))
        violation("electrical idle without an EIOS before it");
      ei_q = !go;
      if (go) for (i = 0; i < 4; i = i + 1) begin
        e = enc(tx_datak[i], tx_data[i * 8 +: 8], i == 0 && tx_compliance ? 1'b0 : trd);
        trd = e[10];
        tq[tw % 64] = e[9:0];
        tw = tw + 1;
        last[i] = tx_data[i * 8 +: 8];
      end
    end
    rx_data <= #(T_CQ) d;
    rx_datak <= #(T_CQ) k;
    rx_status <= #(T_CQ) st;
    rx_valid <= #(T_CQ) v;
    phy_status <= #(T_CQ) ps;
    rx_elecidle <= #(T_CQ) line_idle;
  end

`ifdef GLS
  // PIPE setup and hold at the PCLK pin, from the macro's liberty
  realtime t_in = 0, t_clk = 0;
  always @(tx_data or tx_datak or tx_elecidle or tx_compliance or tx_detectrx_loopback or rx_polarity or powerdown) begin
    t_in = $realtime;
    if (reset_n && ready && t_clk > 0 && $realtime - t_clk < T_HOLD) violation("PIPE hold");
  end
  always @(posedge pclk) begin
    if (reset_n && ready && $realtime - t_in < T_SETUP) violation("PIPE setup");
    t_clk = $realtime;
  end
`endif
endmodule
