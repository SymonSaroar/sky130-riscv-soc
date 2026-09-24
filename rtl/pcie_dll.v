// PCIe data link layer for an x1 link, four symbols per clock, symbol 0 in bits 7:0.
// Receive: STP and SDP at any symbol position, packets back to back. TLP content is gathered into DWs aligned to
// the header; the LCRC runs one DW per clock, one DW behind, so the last DW is the received LCRC. DLLPs are
// checked against their CRC. Transmit: packets start on word boundaries and fill whole words. TLPs of three
// header DWs and up to one data DW get a sequence number and an LCRC (one byte per clock) and wait in a four
// entry retry buffer indexed by the sequence number. Ack/Nak, replay, and flow control follow chapter 3 and
// section 2.6 of the base specification: Posted and Completion credits advertised infinite, Non-Posted 4 and 4.
module pcie_dll (
  input              clk,
  input              rst,
  input              link_up,
  input              l0,
  input       [31:0] d_data,
  input        [3:0] d_k,
  input        [3:0] d_err,
  input              d_en,
  output      [31:0] l_data,
  output       [3:0] l_k,
  output             l_busy,
  input              l_ok,
  output reg         retrain,
  // TLPs to send: three header DWs, byte 0 in bits 7:0, and one data DW if t_wd
  input              t_valid,
  input       [95:0] t_hdr,
  input       [31:0] t_dat,
  input              t_wd,
  input        [1:0] t_fc,      // 0 Posted, 1 Non-Posted, 2 Completion
  output             t_ready,
  // TLPs received: the first five DWs and the number of DWs of header, data and digest
  output reg         r_valid,
  output reg [159:0] r_tlp,
  output reg   [5:0] r_ndw,
  input              np_free,   // one received Non-Posted TLP consumed
  input        [3:0] np_free_d, // its data credits
  output             dl_up,
  output reg   [7:0] replays,
  output reg         e_tlp,
  output reg         e_dllp,
  output reg         e_rx
);
  localparam [7:0]  STP = 8'hFB, SDP = 8'h5C, END = 8'hFD, EDB = 8'hFE;
  localparam [1:0]  DL_INACTIVE = 2'd0, DL_INIT1 = 2'd1, DL_INIT2 = 2'd2, DL_ACTIVE = 2'd3;
  localparam [12:0] REPLAY_LIMIT = 13'd7000;   // 28,000 symbol times
  localparam [10:0] UPDATE_LIMIT = 11'd1875;   // 30 us
  localparam [5:0]  ACK_LIMIT    = 6'd32;      // 128 symbol times
  localparam [7:0]  NP_CREDITS   = 8'd4;

  // reflected CRC-32 (LCRC, polynomial 04C11DB7h): bytes go on the wire as ~crc[7:0] first
  function [31:0] crc8(input [31:0] c, input [7:0] b);
    integer n; reg [31:0] x;
    begin
      x = c ^ {24'b0, b};
      for (n = 0; n < 8; n = n + 1) x = x[0] ? (x >> 1) ^ 32'hEDB8_8320 : x >> 1;
      crc8 = x;
    end
  endfunction
  function [31:0] crc32w(input [31:0] c, input [31:0] w);
    crc32w = crc8(crc8(crc8(crc8(c, w[7:0]), w[15:8]), w[23:16]), w[31:24]);
  endfunction
  // DLLP CRC (polynomial 100Bh): DLLP byte 4 takes bits 7:0
  function [15:0] crc16(input [31:0] d);
    integer n; reg [15:0] x;
    begin
      x = 16'hFFFF;
      for (n = 0; n < 32; n = n + 1) x = (x[0] ^ d[n]) ? (x >> 1) ^ 16'hD008 : x >> 1;
      crc16 = ~x;
    end
  endfunction
  // a DLLP as two words: SDP, bytes 0 to 3, CRC, END
  function [63:0] dllp(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3);
    reg [15:0] c;
    begin
      c = crc16({b3, b2, b1, b0});
      dllp = {END, c[15:8], c[7:0], b3, b2, b1, b0, SDP};
    end
  endfunction
  function [63:0] fcdllp(input [7:0] t, input [7:0] hdr, input [11:0] dat);
    fcdllp = dllp(t, {2'b00, hdr[7:2]}, {hdr[1:0], 2'b00, dat[11:8]}, dat[7:0]);
  endfunction

  // ---------------- receive: framing ----------------
  reg  [1:0] pm;            // 0 between packets, 1 in a DLLP, 2 in a TLP
  reg  [2:0] pc;            // DLLP bytes, or TLP sequence bytes
  reg [47:0] dbuf;
  reg [15:0] pseq;
  reg [23:0] abuf;
  reg  [1:0] an;
  reg  [5:0] nch;           // TLP DWs so far
  reg        pbad;

  reg  [1:0] m, a;
  reg  [2:0] c;
  reg [47:0] db;
  reg [15:0] sq;
  reg [23:0] ab;
  reg  [5:0] n;
  reg        bd, ch_v, ch_first, te_v, te_null, te_bad, dv, dv_bad, rxe;
  reg [31:0] ch_d;
  reg  [5:0] ch_i, te_n;
  reg [15:0] te_seq;
  reg [47:0] dv_d;
  reg  [7:0] s;
  reg        k;
  integer    i;
  always @* begin
    m = pm; c = pc; db = dbuf; sq = pseq; ab = abuf; a = an; n = nch; bd = pbad;
    ch_v = 1'b0; ch_first = 1'b0; ch_d = 32'h0; ch_i = 6'd0;
    te_v = 1'b0; te_null = 1'b0; te_bad = 1'b0; te_n = 6'd0; te_seq = 16'h0;
    dv = 1'b0; dv_bad = 1'b0; dv_d = 48'h0; rxe = 1'b0;
    for (i = 0; i < 4; i = i + 1) begin
      s = d_data[i * 8 +: 8]; k = d_k[i];
      if (!d_en) m = 2'd0;
      else begin
        if (d_err[i]) begin rxe = 1'b1; if (m != 2'd0) bd = 1'b1; end
        if (m == 2'd1) begin
          if (k) begin
            dv = 1'b1; dv_d = db; dv_bad = bd || s != END || c != 3'd6; m = 2'd0;
          end else if (c == 3'd6) bd = 1'b1;
          else begin db[c * 8 +: 8] = s; c = c + 3'd1; end
        end else if (m == 2'd2) begin
          if (k) begin
            te_v = 1'b1; te_null = s == EDB; te_seq = sq; te_n = n;
            te_bad = bd || !(s == END || s == EDB) || a != 2'd0 || c != 3'd2 || n < 6'd4;
            m = 2'd0;
          end else if (c != 3'd2) begin sq = {sq[7:0], s}; c = c + 3'd1; end
          else if (a == 2'd3) begin
            ch_v = 1'b1; ch_d = {s, ab}; ch_i = n; ch_first = n == 6'd0; a = 2'd0;
            if (n >= 6'd40) bd = 1'b1; else n = n + 6'd1;
          end else begin ab[a * 8 +: 8] = s; a = a + 2'd1; end
        end
        // a start symbol opens a packet, also right after a packet cut short by it
        if (m == 2'd0 && k && !d_err[i] && s == STP) begin m = 2'd2; c = 3'd0; a = 2'd0; n = 6'd0; bd = 1'b0; end
        if (m == 2'd0 && k && !d_err[i] && s == SDP) begin m = 2'd1; c = 3'd0; bd = 1'b0; end
      end
    end
  end

  reg        q_ch_v, q_ch_first, q_te_v, q_te_null, q_te_bad, q_dv, q_dv_bad;
  reg [31:0] q_ch_d;
  reg  [5:0] q_ch_i, q_te_n;
  reg [15:0] q_seq, q_te_seq;
  reg [47:0] q_dv_d;
  always @(posedge clk) begin
    pm <= m; pc <= c; dbuf <= db; pseq <= sq; abuf <= ab; an <= a; nch <= n; pbad <= bd;
    q_ch_v <= ch_v; q_ch_first <= ch_first; q_ch_d <= ch_d; q_ch_i <= ch_i; q_seq <= sq;
    q_te_v <= te_v; q_te_null <= te_null; q_te_bad <= te_bad; q_te_n <= te_n; q_te_seq <= te_seq;
    q_dv <= dv; q_dv_bad <= dv_bad; q_dv_d <= dv_d;
    e_rx <= rxe;
    if (rst) begin pm <= 2'd0; q_ch_v <= 1'b0; q_te_v <= 1'b0; q_dv <= 1'b0; end
  end

  // LCRC one DW behind, header DWs, and the check one clock after the end
  reg [31:0] crc, pend;
  reg [31:0] hdr0, hdr1, hdr2, hdr3, hdr4;
  reg        chk, chk_null, chk_bad;
  reg  [5:0] chk_n;
  reg [11:0] chk_seq;
  always @(posedge clk) begin
    if (q_ch_v) begin
      crc  <= q_ch_first ? crc8(crc8(32'hFFFF_FFFF, q_seq[15:8]), q_seq[7:0]) : crc32w(crc, pend);
      pend <= q_ch_d;
      case (q_ch_i)
        6'd0: hdr0 <= q_ch_d;
        6'd1: hdr1 <= q_ch_d;
        6'd2: hdr2 <= q_ch_d;
        6'd3: hdr3 <= q_ch_d;
        6'd4: hdr4 <= q_ch_d;
        default: ;
      endcase
    end
    chk <= q_te_v && !rst; chk_null <= q_te_null; chk_bad <= q_te_bad; chk_n <= q_te_n; chk_seq <= q_te_seq[11:0];
  end
  wire lcrc_ok  = pend == ~crc;
  wire lcrc_inv = pend == crc;

  // DLLP CRC check
  reg       dl_ok;
  reg [7:0] db0, db1, db2, db3;
  always @(posedge clk) begin
    dl_ok  <= q_dv && !q_dv_bad && crc16(q_dv_d[31:0]) == {q_dv_d[47:40], q_dv_d[39:32]} && !rst;
    e_dllp <= q_dv && !(!q_dv_bad && crc16(q_dv_d[31:0]) == {q_dv_d[47:40], q_dv_d[39:32]});
    {db3, db2, db1, db0} <= q_dv_d[31:0];
  end

  // ---------------- link state, credits, sequence numbers ----------------
  reg  [1:0] dl_st;
  reg  [2:0] fi1;
  reg        fi2;
  reg  [7:0] lim_ph, lim_nph, cons_ph, cons_nph, alloc_nph;
  reg [11:0] lim_pd, lim_npd, cons_pd, cons_npd, alloc_npd;
  reg        inf_ph, inf_pd, inf_nph, inf_npd;
  reg [11:0] next_tx, ackd, sp, nb, next_rcv;
  reg        nak_sched, nak_req, ack_pend, ack_now, upd_req, rt_on, replaying;
  reg  [5:0] ack_t;
  reg [10:0] upd_t;
  reg [12:0] rt;
  reg  [1:0] rnum;
  assign dl_up = dl_st == DL_INIT2 || dl_st == DL_ACTIVE;

  wire [11:0] outst = next_tx - ackd - 12'd1;
  function gate8(input [7:0] lim, input [7:0] req); gate8 = ((lim - req) & 8'hFF) <= 8'd128; endfunction
  function gate12(input [11:0] lim, input [11:0] req); gate12 = ((lim - req) & 12'hFFF) <= 12'd2048; endfunction
  // credit and retry buffer checks, a clock old: the builder is busy for 14 clocks after every TLP it takes
  reg  p_h_ok, p_d_ok, np_h_ok, np_d_ok, rb_room;
  always @(posedge clk) begin
    p_h_ok  <= inf_ph || gate8(lim_ph, cons_ph + 8'd1);
    p_d_ok  <= inf_pd || gate12(lim_pd, cons_pd + 12'd1);
    np_h_ok <= inf_nph || gate8(lim_nph, cons_nph + 8'd1);
    np_d_ok <= inf_npd || gate12(lim_npd, cons_npd + 12'd1);
    rb_room <= outst < 12'd4;
  end
  wire fc_ok = t_fc == 2'd0 ? p_h_ok && (!t_wd || p_d_ok) : t_fc == 2'd1 ? np_h_ok && (!t_wd || np_d_ok) : 1'b1;

  // ---------------- transmit: TLP builder and retry buffer ----------------
  reg         bld, bwd;
  reg  [11:0] bseq;
  reg [143:0] bsr;           // sequence number, header and data bytes for the LCRC
  reg   [4:0] bcnt;
  reg  [31:0] bcrc;
  reg [191:0] bfb;           // the framed TLP
  reg [191:0] rbw [0:3];
  reg   [3:0] rb6;           // entry is six words
  assign t_ready = dl_st == DL_ACTIVE && !bld && !replaying && rb_room && fc_ok;
  wire [31:0] lc = ~bcrc;

  // ---------------- transmit: word engine ----------------
  reg [191:0] pk;
  reg   [2:0] pk_n, pi;
  reg         mid, pk_tlp;
  reg  [63:0] ack_w, nak_w, upd_w;
  reg   [1:0] ir;              // InitFC rotation
  wire [11:0] rcv_last = next_rcv - 12'd1;

  wire ack_due = (ack_now || (ack_pend && ack_t >= ACK_LIMIT)) && !nak_sched;
  wire [2:0] sel = dl_st == DL_ACTIVE && nak_req ? 3'd1 :
                   dl_st == DL_ACTIVE && ack_due ? 3'd2 :
                   dl_st == DL_ACTIVE && upd_req ? 3'd3 :
                   dl_st == DL_ACTIVE && sp != nb ? 3'd4 :
                   dl_st == DL_INIT1 || dl_st == DL_INIT2 ? 3'd5 : 3'd0;
  wire [7:0]  ift = (dl_st == DL_INIT1 ? 8'h40 : 8'hC0) | {2'b00, ir, 4'h0};
  wire [63:0] init_w = ir == 2'd1 ? fcdllp(ift, NP_CREDITS, {4'd0, NP_CREDITS}) : fcdllp(ift, 8'd0, 12'd0);
  wire [191:0] rb_sp = rbw[sp[1:0]];
  wire [63:0]  sel_d = sel == 3'd1 ? nak_w : sel == 3'd2 ? ack_w : sel == 3'd3 ? upd_w : init_w;
  assign l_data = mid ? pk[pi * 32 +: 32] : sel == 3'd0 ? 32'h0 : sel == 3'd4 ? rb_sp[31:0] : sel_d[31:0];
  assign l_k    = mid ? (pi == pk_n - 3'd1 ? 4'b1000 : 4'b0000) : sel == 3'd0 ? 4'b0000 : 4'b0001;
  assign l_busy = mid;

  wire        rx_dllp = dl_ok;
  wire  [3:0] fct = db0[7:4];
  wire  [7:0] fch = {db1[5:0], db2[7:6]};
  wire [11:0] fcd = {db2[3:0], db3};
  wire [11:0] ans = {db2[3:0], db3};
  wire        an_ok = ((ans - ackd) & 12'hFFF) < 12'd2048 && (((next_tx - 12'd1) - ans) & 12'hFFF) <= 12'd2048;

  always @(posedge clk) begin
    r_valid <= 1'b0; e_tlp <= 1'b0; retrain <= 1'b0;
    ack_w <= dllp(8'h00, 8'h00, {4'h0, rcv_last[11:8]}, rcv_last[7:0]);
    nak_w <= dllp(8'h10, 8'h00, {4'h0, rcv_last[11:8]}, rcv_last[7:0]);
    upd_w <= fcdllp(8'h90, alloc_nph, alloc_npd);

    // data link state
    case (dl_st)
      DL_INACTIVE: if (link_up) dl_st <= DL_INIT1;
      DL_INIT1:    if (fi1 == 3'b111) dl_st <= DL_INIT2;
      DL_INIT2:    if (fi2) dl_st <= DL_ACTIVE;
      default: ;
    endcase

    // transmit words
    if (l_ok) begin
      if (mid) begin
        pi <= pi + 3'd1;
        if (pi + 3'd1 == pk_n) begin
          mid <= 1'b0;
          if (pk_tlp && !rt_on) begin rt_on <= 1'b1; rt <= 13'd0; end
        end
      end else if (sel != 3'd0) begin
        mid <= 1'b1; pi <= 3'd1; pk_tlp <= sel == 3'd4;
        if (sel == 3'd4) begin pk <= rb_sp; pk_n <= rb6[sp[1:0]] ? 3'd6 : 3'd5; sp <= sp + 12'd1; end
        else begin pk <= {128'h0, sel_d}; pk_n <= 3'd2; end
        case (sel)
          3'd1: nak_req <= 1'b0;
          3'd2: begin ack_now <= 1'b0; ack_pend <= 1'b0; ack_t <= 6'd0; end
          3'd3: begin upd_req <= 1'b0; upd_t <= 11'd0; end
          3'd5: ir <= ir == 2'd2 ? 2'd0 : ir + 2'd1;
          default: ;
        endcase
      end
    end


    // received TLP
    if (chk && dl_up) begin
      if (chk_null && lcrc_inv) ;
      else if (chk_bad || chk_null || !lcrc_ok) begin
        e_tlp <= 1'b1;
        if (!nak_sched) begin nak_req <= 1'b1; nak_sched <= 1'b1; ack_t <= 6'd0; end
      end else if (chk_seq == next_rcv) begin
        r_valid <= 1'b1; r_tlp <= {hdr4, hdr3, hdr2, hdr1, hdr0}; r_ndw <= chk_n - 6'd1;
        next_rcv <= next_rcv + 12'd1; nak_sched <= 1'b0;
        if (!ack_pend) ack_t <= 6'd0;
        ack_pend <= 1'b1;
        if (dl_st == DL_INIT2) fi2 <= 1'b1;
      end else if (((next_rcv - chk_seq) & 12'hFFF) <= 12'd2048) ack_now <= 1'b1;
      else begin
        e_tlp <= 1'b1;
        if (!nak_sched) begin nak_req <= 1'b1; nak_sched <= 1'b1; ack_t <= 6'd0; end
      end
    end
    if (ack_pend && ack_t != 6'h3F) ack_t <= ack_t + 6'd1;

    // received DLLP
    if (rx_dllp) case (fct)
      4'h0, 4'h1: if (dl_st == DL_ACTIVE) begin
        if (ans != ackd && an_ok) begin
          ackd <= ans; rnum <= 2'd0;
          if (ans == next_tx - 12'd1) rt_on <= 1'b0; else rt <= 13'd0;
        end
        if (fct == 4'h1 && (ans == ackd || an_ok) && ans != next_tx - 12'd1) begin
          sp <= ans + 12'd1; replaying <= 1'b1; rt_on <= 1'b0; rt <= 13'd0;
          rnum <= ans != ackd ? 2'd1 : rnum + 2'd1;
          if (ans == ackd && rnum == 2'd3) retrain <= 1'b1;
          replays <= replays == 8'hFF ? replays : replays + 8'd1;
        end
      end
      4'h4, 4'h5, 4'h6, 4'hC, 4'hD, 4'hE: if (db0[3:0] == 4'h0) begin
        if (dl_st == DL_INIT1) case (db0[5:4])
          2'b00: begin lim_ph <= fch; lim_pd <= fcd; inf_ph <= fch == 8'd0; inf_pd <= fcd == 12'd0; fi1[0] <= 1'b1; end
          2'b01: begin lim_nph <= fch; lim_npd <= fcd; inf_nph <= fch == 8'd0; inf_npd <= fcd == 12'd0; fi1[1] <= 1'b1; end
          default: fi1[2] <= 1'b1;
        endcase
        if (dl_st == DL_INIT2 && db0[7]) fi2 <= 1'b1;
      end
      4'h8, 4'h9, 4'hA: if (db0[3:0] == 4'h0 && dl_up) begin
        if (dl_st == DL_INIT2) fi2 <= 1'b1;
        if (db0[5:4] == 2'b00) begin if (!inf_ph) lim_ph <= fch; if (!inf_pd) lim_pd <= fcd; end
        if (db0[5:4] == 2'b01) begin if (!inf_nph) lim_nph <= fch; if (!inf_npd) lim_npd <= fcd; end
      end
      default: ;
    endcase

    // replay timer: runs in L0 while TLPs are outstanding
    if (rt_on && l0) begin
      rt <= rt + 13'd1;
      if (rt >= REPLAY_LIMIT) begin
        sp <= ackd + 12'd1; replaying <= 1'b1; rt_on <= 1'b0; rt <= 13'd0; rnum <= rnum + 2'd1;
        if (rnum == 2'd3) retrain <= 1'b1;
        replays <= replays == 8'hFF ? replays : replays + 8'd1;
      end
    end
    if (replaying && sp == nb && !(rx_dllp && fct == 4'h1)) replaying <= 1'b0;

    // Non-Posted credits come back as the transaction layer consumes the TLPs
    if (np_free) begin alloc_nph <= alloc_nph + 8'd1; alloc_npd <= alloc_npd + {8'd0, np_free_d}; upd_req <= 1'b1; end
    if (dl_st == DL_ACTIVE && l0) begin
      upd_t <= upd_t + 11'd1;
      if (upd_t >= UPDATE_LIMIT) begin upd_req <= 1'b1; upd_t <= 11'd0; end
    end

    // build a TLP: one LCRC byte per clock, then into the retry buffer
    if (t_valid && t_ready) begin
      bld <= 1'b1; bseq <= next_tx; next_tx <= next_tx + 12'd1; bwd <= t_wd;
      bsr <= {t_dat, t_hdr, next_tx[7:0], 4'h0, next_tx[11:8]};
      bcnt <= t_wd ? 5'd18 : 5'd14; bcrc <= 32'hFFFF_FFFF;
      bfb <= {40'h0, t_dat, t_hdr, next_tx[7:0], 4'h0, next_tx[11:8], STP};
      case (t_fc)
        2'd0: begin cons_ph <= cons_ph + 8'd1; if (t_wd) cons_pd <= cons_pd + 12'd1; end
        2'd1: begin cons_nph <= cons_nph + 8'd1; if (t_wd) cons_npd <= cons_npd + 12'd1; end
        default: ;
      endcase
    end else if (bld && bcnt != 5'd0) begin
      bcrc <= crc8(bcrc, bsr[7:0]); bsr <= bsr >> 8; bcnt <= bcnt - 5'd1;
    end else if (bld) begin
      rbw[bseq[1:0]] <= bwd ? {END, lc[31:24], lc[23:16], lc[15:8], lc[7:0], bfb[151:0]}
                            : {32'h0, END, lc[31:24], lc[23:16], lc[15:8], lc[7:0], bfb[119:0]};
      rb6[bseq[1:0]] <= bwd;
      bld <= 1'b0; nb <= bseq + 12'd1;
    end

    if (rst || !link_up) begin
      dl_st <= DL_INACTIVE; fi1 <= 3'b000; fi2 <= 1'b0;
      next_tx <= 12'd0; ackd <= 12'hFFF; sp <= 12'd0; nb <= 12'd0; next_rcv <= 12'd0;
      nak_sched <= 1'b0; nak_req <= 1'b0; ack_pend <= 1'b0; ack_now <= 1'b0; ack_t <= 6'd0;
      upd_req <= 1'b0; upd_t <= 11'd0; rt_on <= 1'b0; rt <= 13'd0; rnum <= 2'd0; replaying <= 1'b0;
      cons_ph <= 8'd0; cons_pd <= 12'd0; cons_nph <= 8'd0; cons_npd <= 12'd0;
      lim_ph <= 8'd0; lim_pd <= 12'd0; lim_nph <= 8'd0; lim_npd <= 12'd0;
      inf_ph <= 1'b0; inf_pd <= 1'b0; inf_nph <= 1'b0; inf_npd <= 1'b0;
      alloc_nph <= NP_CREDITS; alloc_npd <= {4'd0, NP_CREDITS};
      bld <= 1'b0; mid <= 1'b0; pi <= 3'd0; pk_n <= 3'd0; pk_tlp <= 1'b0; ir <= 2'd0;
    end
    if (rst) replays <= 8'd0;
  end
endmodule
