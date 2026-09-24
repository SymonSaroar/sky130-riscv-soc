`timescale 1ns/1ps
// TI XIO1100 model from its data manual (SLLS690C): TI-PIPE in 16-bit SDR mode on the MAC side, one symbol per
// strobe on the link side. RX_CLK runs at 125 MHz; outputs change TCO after its rising edge. Transmit data is
// sampled on TX_CLK rising. The receive path encodes the link partner's symbols in 8b/10b, inverts the bits when
// the lane polarity is swapped and RX_POLARITY does not undo it, decodes them, and passes them through an elastic
// buffer that adds or removes one SKP per SKP ordered set. Violations of the MAC rules count in `errors`.
// Plusargs: +phy_swap (lane polarity swapped), +phy_dec_err=N (decode error on the Nth data symbol of a packet).
module xio1100 (
  input             reset_n,
  input       [1:0] powerdown,
  input             tx_clk,
  input      [15:0] tx_data,
  input       [1:0] tx_datak,
  input             tx_elecidle,
  input             tx_compliance,
  input             tx_det_lb,
  input             rx_polarity,
  output reg        rx_clk,
  output reg [15:0] rx_data,
  output reg  [1:0] rx_datak,
  output reg  [2:0] rx_status,
  output reg        rx_valid,
  output reg        phy_status,
  output reg        rx_elecidle,
  // link side
  output reg  [7:0] lt_sym,
  output reg        lt_k,
  output reg        lt_idle,
  output reg        lt_stb,
  input       [7:0] lr_sym,
  input             lr_k,
  input             lr_idle,
  input             lr_stb
);
  localparam real TCO = 1.4;
  localparam [1:0] P0 = 2'b00, P1 = 2'b10;
  localparam [7:0] COM = 8'hBC, SKP = 8'h1C, IDL = 8'h7C, EDB = 8'hFE, STP = 8'hFB, SDP = 8'h5C, END = 8'hFD;
  integer errors = 0;

  initial begin
    rx_clk = 0; rx_data = 0; rx_datak = 0; rx_status = 0; rx_valid = 0; phy_status = 1; rx_elecidle = 1;
    lt_sym = 0; lt_k = 0; lt_idle = 1; lt_stb = 0;
  end
  always #4 rx_clk = !rx_clk;

  task violation(input [8*64-1:0] what);
    begin errors = errors + 1; $display("XIO1100 VIOLATION at %0t ns: %0s", $time, what); end
  endtask

  // ---------------- 8b/10b ----------------
  function integer ones(input [5:0] v); ones = v[0] + v[1] + v[2] + v[3] + v[4] + v[5]; endfunction

  // 5b/6b at negative running disparity; the code at positive disparity is the complement when unbalanced and for D.07
  function [5:0] t6(input [4:0] x);
    case (x)
      5'd0: t6 = 6'b100111; 5'd1: t6 = 6'b011101; 5'd2: t6 = 6'b101101; 5'd3: t6 = 6'b110001;
      5'd4: t6 = 6'b110101; 5'd5: t6 = 6'b101001; 5'd6: t6 = 6'b011001; 5'd7: t6 = 6'b111000;
      5'd8: t6 = 6'b111001; 5'd9: t6 = 6'b100101; 5'd10: t6 = 6'b010101; 5'd11: t6 = 6'b110100;
      5'd12: t6 = 6'b001101; 5'd13: t6 = 6'b101100; 5'd14: t6 = 6'b011100; 5'd15: t6 = 6'b010111;
      5'd16: t6 = 6'b011011; 5'd17: t6 = 6'b100011; 5'd18: t6 = 6'b010011; 5'd19: t6 = 6'b110010;
      5'd20: t6 = 6'b001011; 5'd21: t6 = 6'b101010; 5'd22: t6 = 6'b011010; 5'd23: t6 = 6'b111010;
      5'd24: t6 = 6'b110011; 5'd25: t6 = 6'b100110; 5'd26: t6 = 6'b010110; 5'd27: t6 = 6'b110110;
      5'd28: t6 = 6'b001110; 5'd29: t6 = 6'b101110; 5'd30: t6 = 6'b011110; default: t6 = 6'b101011;
    endcase
  endfunction

  // encode {k, byte} at running disparity rd (1 = positive): {rd after, abcdei, fghj}
  function [10:0] enc(input k, input [7:0] b, input rd);
    reg [5:0] s6; reg [3:0] s4; reg r1;
    begin
      s6 = k && b[4:0] == 5'd28 ? 6'b001111 : t6(b[4:0]);
      if (rd && (ones(s6) != 3 || (!k && b[4:0] == 5'd7))) s6 = ~s6;
      r1 = ones(s6) == 3 ? rd : !rd;
      if (k) case (b[7:5])
        3'd0: s4 = r1 ? 4'b0100 : 4'b1011;  3'd1: s4 = r1 ? 4'b1001 : 4'b0110;
        3'd2: s4 = r1 ? 4'b0101 : 4'b1010;  3'd3: s4 = r1 ? 4'b0011 : 4'b1100;
        3'd4: s4 = r1 ? 4'b0010 : 4'b1101;  3'd5: s4 = r1 ? 4'b1010 : 4'b0101;
        3'd6: s4 = r1 ? 4'b0110 : 4'b1001;  default: s4 = r1 ? 4'b1000 : 4'b0111;
      endcase else case (b[7:5])
        3'd0: s4 = r1 ? 4'b0100 : 4'b1011;  3'd1: s4 = 4'b1001;
        3'd2: s4 = 4'b0101;                 3'd3: s4 = r1 ? 4'b0011 : 4'b1100;
        3'd4: s4 = r1 ? 4'b0010 : 4'b1101;  3'd5: s4 = 4'b1010;
        3'd6: s4 = 4'b0110;
        default: s4 = (!r1 && (b[4:0] == 17 || b[4:0] == 18 || b[4:0] == 20)) ? 4'b0111 :
                      (r1 && (b[4:0] == 11 || b[4:0] == 13 || b[4:0] == 14)) ? 4'b1000 :
                      r1 ? 4'b0001 : 4'b1110;
      endcase
      enc = {(s4[0] + s4[1] + s4[2] + s4[3]) == 2 ? r1 : !r1, s6, s4};
    end
  endfunction

  // decode table: {valid, k, byte} for every 10-bit code
  reg [9:0] dtab [0:1023];
  initial begin : build
    integer c, v; reg [10:0] e;
    for (c = 0; c < 1024; c = c + 1) dtab[c] = 10'b0;
    for (v = 0; v < 512; v = v + 1)
      if (!v[8] || v[4:0] == 28 || (v[7:5] == 7 && (v[4:0] == 23 || v[4:0] == 27 || v[4:0] == 29 || v[4:0] == 30))) begin
        e = enc(v[8], v[7:0], 1'b0); dtab[e[9:0]] = {1'b1, v[8], v[7:0]};
        e = enc(v[8], v[7:0], 1'b1); dtab[e[9:0]] = {1'b1, v[8], v[7:0]};
      end
  end

  // ---------------- MAC side control ----------------
  reg  [1:0] pstate = P1;
  reg        ready = 0, pol_on = 0, swap = 0, locked = 0, started = 0, os_adj = 0, rdx = 0, in_pkt = 0;
  reg        after_com = 0;
  integer    rcnt = 0, pcnt = 0, dcnt = 0, dhold = 0, polcnt = 0, dec_err_at = 0, dsym = 0, coms = 0;
  integer    wp = 0, rp = 0, com_i = 0;
  reg  [7:0] eb_sym [0:63];
  reg        eb_k [0:63];
  reg  [2:0] eb_st [0:63];
  initial begin
    swap = $test$plusargs("phy_swap");
    if (!$value$plusargs("phy_dec_err=%d", dec_err_at)) dec_err_at = 0;
  end

  always @(posedge rx_clk) begin : mac
    reg        ps, v, k0, k1;
    reg  [2:0] st, t0, t1;
    reg  [7:0] s0, s1;
    ps = 0; st = 3'b000; v = 0; s0 = 0; s1 = 0; k0 = 0; k1 = 0;
    if (!reset_n) begin
      ready = 0; rcnt = 0; pstate = P1; ps = 1; pcnt = 0; dcnt = 0; dhold = 0;
      if (tx_det_lb === 1'b1 || tx_elecidle === 1'b0 || tx_compliance === 1'b1 || rx_polarity === 1'b1 ||
          powerdown === P0) violation("TI-PIPE inputs not at their reset values during reset");
    end else if (!ready) begin
      rcnt = rcnt + 1; ps = 1;
      if (rcnt == 2) begin ready = 1; ps = 0; pstate = powerdown; end
    end else begin
      // power state changes end with PHY_STATUS for one cycle
      if (pcnt != 0) begin
        pcnt = pcnt - 1;
        if (pcnt == 0) begin pstate = powerdown; ps = 1; end
      end else if (powerdown != pstate) pcnt = 4;
      // receiver detection in P1
      if (dcnt != 0) begin
        dcnt = dcnt - 1;
        if (dcnt == 0) begin ps = 1; st = 3'b011; dhold = 1; end
      end else if (dhold != 0) begin
        if (!tx_det_lb) dhold = 0;
        else if (dhold > 64) begin violation("TxDetectRx held after the detection completed"); dhold = 0; end
        else dhold = dhold + 1;
      end else if (pstate == P1 && tx_det_lb) dcnt = 100;
      if (pstate != P1 && tx_det_lb && !tx_elecidle) violation("loopback requested");
      // RX_POLARITY takes effect within 20 clocks
      if (rx_polarity != pol_on) begin
        polcnt = polcnt + 1;
        if (polcnt == 12) begin pol_on = rx_polarity; polcnt = 0; end
      end else polcnt = 0;
      // two symbols out of the elastic buffer
      if (locked && pstate != P1) begin
        if (!started && wp - rp >= 8) started = 1;
        if (started) begin
          v = 1;
          if (wp - rp < 2) begin
            s0 = EDB; k0 = 1; s1 = EDB; k1 = 1; st = 3'b110;
          end else begin
            s0 = eb_sym[rp % 64]; k0 = eb_k[rp % 64]; t0 = eb_st[rp % 64];
            s1 = eb_sym[(rp + 1) % 64]; k1 = eb_k[(rp + 1) % 64]; t1 = eb_st[(rp + 1) % 64];
            rp = rp + 2;
            st = t0 == 3'b100 || t1 == 3'b100 ? 3'b100 : t0[2] ? t0 : t1[2] ? t1 : t0 != 0 ? t0 : t1;
          end
        end
      end
    end
    rx_data <= #(TCO) {s1, s0};
    rx_datak <= #(TCO) {k1, k0};
    rx_status <= #(TCO) st;
    rx_valid <= #(TCO) v;
    phy_status <= #(TCO) ps;
  end

  // ---------------- transmit: TX_CLK to the link ----------------
  reg [7:0] last0 = 0, last1 = 0, last2 = 0, last3 = 0;
  reg       ei_q = 1;
  realtime  t_tx = 0, t_clk = 0;
  always @(tx_data or tx_datak or tx_elecidle) begin
    t_tx = $realtime;
    if (reset_n && ready && pstate == P0 && t_clk > 0 && $realtime - t_clk < 0.1) violation("TX hold");
  end
  always @(posedge tx_clk) begin : tx
    reg [7:0] s0, s1; reg k0, k1, go;
    t_clk = $realtime;
    go = reset_n && ready && pstate == P0 && !tx_elecidle;
    if (go && $realtime - t_tx < 1.3) violation("TX setup");
    if (reset_n && ready && pstate == P0 && tx_elecidle && !ei_q &&
        !(last0 == COM && last1 == IDL && last2 == IDL && last3 == IDL))
      violation("electrical idle without an EIOS before it");
    ei_q = !go;
    lt_idle <= #(0.2) !go;
    if (go) begin
      s0 = tx_data[7:0]; k0 = tx_datak[0]; s1 = tx_data[15:8]; k1 = tx_datak[1];
      last0 = last2; last1 = last3; last2 = s0; last3 = s1;
      #0.5 lt_sym = s0; lt_k = k0; lt_stb = 1;
      #1   lt_stb = 0;
      #1   lt_sym = s1; lt_k = k1; lt_stb = 1;
      #1   lt_stb = 0;
    end
  end

  // ---------------- receive: link to the elastic buffer ----------------
  always @(lr_idle) rx_elecidle <= #(2) lr_idle;
  always @(posedge lr_idle) begin locked = 0; started = 0; coms = 0; wp = 0; rp = 0; in_pkt = 0; end

  always @(posedge lr_stb) if (!lr_idle && reset_n && ready && pstate != P1) begin : rx
    reg [10:0] e;
    reg  [9:0] c, d;
    reg  [2:0] st;
    // 8b/10b round trip, bits inverted while the swap is not undone
    e = enc(lr_k, lr_sym, rdx);
    rdx = e[10];
    c = swap != pol_on ? ~e[9:0] : e[9:0];
    d = dtab[c];
    st = d[9] ? 3'b000 : 3'b100;
    if (!d[9]) d = {1'b0, 1'b1, EDB};
    if (d[9] && !d[8] && in_pkt) begin
      dsym = dsym + 1;
      if (dsym == dec_err_at) begin st = 3'b100; d = {1'b0, 1'b1, EDB}; end
    end
    if (d[8] && (d[7:0] == STP || d[7:0] == SDP)) in_pkt = 1;
    if (d[8] && (d[7:0] == END || d[7:0] == EDB)) in_pkt = 0;
    if (!locked) begin
      if (d[8] && d[7:0] == COM) coms = coms + 1;
      if (coms >= 2) begin locked = 1; started = 0; wp = 0; rp = 0; end
    end
    if (locked) begin
      if (d[8] && d[7:0] == COM) begin
        com_i = wp; after_com = 1; os_adj = 0; push(d[7:0], 1'b1, st);
      end else if (after_com && d[8] && d[7:0] == SKP && !os_adj && started && wp - rp > 12) begin
        eb_st[com_i % 64] = 3'b010; os_adj = 1;                // one SKP removed
      end else if (after_com && d[8] && d[7:0] == SKP && !os_adj && started && wp - rp < 5) begin
        eb_st[com_i % 64] = 3'b001; os_adj = 1;                // one SKP added
        push(SKP, 1'b1, 3'b000); push(SKP, 1'b1, 3'b000);
      end else begin
        if (!(d[8] && d[7:0] == SKP)) after_com = 0;
        push(d[7:0], d[8], st);
      end
      if (wp - rp > 60) begin violation("elastic buffer overflow"); rp = wp - 8; end
    end
  end

  task push(input [7:0] s, input k, input [2:0] st);
    begin eb_sym[wp % 64] = s; eb_k[wp % 64] = k; eb_st[wp % 64] = st; wp = wp + 1; end
  endtask
endmodule
