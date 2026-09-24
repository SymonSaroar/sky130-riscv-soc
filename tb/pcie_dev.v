`timescale 1ns/1ps
// PCIe endpoint model, written from the base specification: an x1 Gen1 Upstream Port at symbol level, one symbol
// per clock of its own 250 MHz reference shifted by +pcie_ppm (default 250). It trains the link, runs the data link
// layer with finite Posted and Non-Posted credits, and has a Type 0 configuration header with one 4 KB memory BAR
// over 1 KB of memory. Everything the root sends is checked; violations count in `errors`.
// Plusargs: +dev_rrs=N (RRS for the first N configuration requests, default 2), +dev_lcrc_err=N (bad LCRC on the
// Nth TLP sent), +dev_nak=N (Nak the Nth TLP received), +dev_hold_ack=N (no Ack for the Nth TLP until the root
// replays it), +dev_recovery=N (enter Recovery after the Nth TLP received), +dev_up_req (send MRd, MWr and a
// Message to the root once bus mastering is enabled), +pcie_tscale=N (divide the timeouts).
module pcie_dev (
  input            perst_n,
  output reg [7:0] tx_sym,
  output reg       tx_k,
  output reg       tx_idle,
  output           tx_stb,
  input      [7:0] rx_sym,
  input            rx_k,
  input            rx_idle,
  input            rx_stb
);
  localparam [7:0] COM = 8'hBC, SKP = 8'h1C, STP = 8'hFB, SDP = 8'h5C, END = 8'hFD, EDB = 8'hFE, PAD = 8'hF7,
                   IDL = 8'h7C, FTS = 8'h3C, TS1 = 8'h4A, TS2 = 8'h45;
  localparam integer DQ = 0, PA = 1, PC = 2, CLS = 3, CLA = 4, CNW = 5, CNA = 6, CC = 7, CI = 8, L0 = 9,
                     RL = 10, RC = 11, RI = 12, HR = 13;
  localparam [15:0] VENDOR = 16'h5A5A, DEVICE = 16'hC0DE;
  integer errors = 0;

  task violation(input [8*80-1:0] what);
    begin errors = errors + 1; $display("PCIE DEV VIOLATION at %0t ns: %0s", $time, what); end
  endtask

  // ---------------- clock and options ----------------
  reg clk = 0;
  real half;
  integer ppm, tscale, rrs_init, lcrc_err_at, nak_at, hold_ack_at, recovery_at;
  reg up_req;
  initial begin
    if (!$value$plusargs("pcie_ppm=%d", ppm)) ppm = 250;
    if (!$value$plusargs("pcie_tscale=%d", tscale)) tscale = 1;
    if (!$value$plusargs("dev_rrs=%d", rrs_init)) rrs_init = 2;
    if (!$value$plusargs("dev_lcrc_err=%d", lcrc_err_at)) lcrc_err_at = 0;
    if (!$value$plusargs("dev_nak=%d", nak_at)) nak_at = 0;
    if (!$value$plusargs("dev_hold_ack=%d", hold_ack_at)) hold_ack_at = 0;
    if (!$value$plusargs("dev_recovery=%d", recovery_at)) recovery_at = 0;
    up_req = $test$plusargs("dev_up_req");
    half = 2.0 * (1.0 - ppm * 1.0e-6);
    tx_sym = 0; tx_k = 0; tx_idle = 1;
  end
  always #(half) clk = !clk;
  assign tx_stb = clk;

  // symbol times
  function integer ms(input real m); ms = m * 250000.0 / tscale; endfunction

  // ---------------- state ----------------
  integer lt = DQ, lt_t = 0, sym_t = 0;      // LTSSM state, time in state, symbols sent
  reg     link_up = 0;
  reg [7:0] link_num = 0, lane_num = 0;
  // received training sets
  integer rx_cnt = 0, ts_tx = 0, ts_tx_after = 0, idle_rx = 0, idle_tx_after = 0;
  reg     rx_seen = 0, rx_ok = 0;
  reg [7:0] last_id, last_link, last_lane, last_ctrl;
  reg     last_link_pad, last_lane_pad;
  reg [7:0] cnw_lane;
  // data link layer
  integer dl = 0;                              // 0 inactive, 1 FC_INIT1, 2 FC_INIT2, 3 active
  reg [2:0] fi1 = 0;
  reg     fi2 = 0;
  integer root_ph, root_pd, root_nph, root_npd, root_cplh, root_cpld;   // limits, -1 = infinite
  integer cons_ph, cons_pd, cons_nph, cons_npd;
  integer next_tx_seq, ackd_seq, next_rcv_seq, replay_t, replay_num, rx_tlps = 0, tx_tlps = 0;
  reg     nak_sched, ack_pend, ack_now, replaying, hold_ack, hold_seen;
  integer ack_t, upd_t, upd_np_t, upd_p_t, init_t;
  integer alloc_ph, alloc_pd, alloc_nph, alloc_npd, recv_ph, recv_pd, recv_nph, recv_npd;
  integer upd_root_np_t;
  // transaction layer
  reg [31:0] cfg [0:15];
  reg [31:0] mem [0:255];
  reg [15:0] my_id = 0;
  integer rrs_left, ur_wait, up_done;
  reg [7:0] up_tag = 8'h10;

  // transmit buffers: the item on the wire, and the retry buffer of TLPs
  reg [7:0] txb [0:8191];       // item bytes at 0..; retry buffer entries at 4096 + 64*i
  reg       txk [0:63];
  integer   tx_len = 0, tx_pos = 0;
  integer   rb_len [0:15];
  reg [11:0] rb_seq [0:15];
  integer   rb_head = 0, rb_tail = 0, rb_replay = 0;
  // pending TLPs from the transaction layer, framed later
  reg [7:0] tq [0:2047];        // 16 entries of up to 128 bytes: header and data
  integer   tq_len [0:15];
  integer   tq_type [0:15];     // 0 posted, 1 non-posted, 2 completion
  integer   tq_head = 0, tq_tail = 0;

  // receive buffers
  reg [7:0] rxb [0:4199];
  reg       rxk [0:4199];
  integer   rx_n = 0, rx_mode = 0;     // 0 none, 1 ordered set, 2 packet
  integer   skp_t = 0, skp_rx = 0;
  reg       was_active = 0;
  wire [11:0] next_rcv_seq_m1 = next_rcv_seq - 1;

  // ---------------- CRCs as written in the specification ----------------
  // DLLP CRC: polynomial 100Bh, seed FFFFh, bit 0 of byte 0 first, result complemented and mapped as table 3-6
  function [15:0] dcrc(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3);
    reg [15:0] c, r, f; reg [31:0] d; integer i;
    begin
      c = 16'hFFFF; d = {b3, b2, b1, b0};
      for (i = 0; i < 32; i = i + 1) c = {c[14:0], 1'b0} ^ ((c[15] ^ d[i]) ? 16'h100B : 16'h0);
      r = ~c;
      for (i = 0; i < 8; i = i + 1) begin f[7 - i] = r[i]; f[15 - i] = r[8 + i]; end
      dcrc = f;                             // bits 15:8 go in DLLP byte 4, bits 7:0 in byte 5
    end
  endfunction

  // LCRC over n bytes of buf starting at s: polynomial 04C11DB7h, seed FFFF_FFFFh, table 3-7
  function [31:0] lcrc(input integer s, input integer n, input integer which);
    reg [31:0] c, r, f; reg [7:0] b; integer i, j;
    begin
      c = 32'hFFFF_FFFF;
      for (i = 0; i < n; i = i + 1) begin
        b = which ? txb[s + i] : rxb[s + i];
        for (j = 0; j < 8; j = j + 1) c = {c[30:0], 1'b0} ^ ((c[31] ^ b[j]) ? 32'h04C1_1DB7 : 32'h0);
      end
      r = ~c;
      for (i = 0; i < 8; i = i + 1) begin
        f[7 - i] = r[i]; f[15 - i] = r[8 + i]; f[23 - i] = r[16 + i]; f[31 - i] = r[24 + i];
      end
      lcrc = f;                             // bits 31:24 go in byte N-3 ... bits 7:0 in byte N
    end
  endfunction

  // ---------------- reset ----------------
  task reset_dll;
    begin
      dl = 0; fi1 = 0; fi2 = 0;
      next_tx_seq = 0; ackd_seq = 4095; next_rcv_seq = 0; replay_t = -1; replay_num = 0;
      nak_sched = 0; ack_pend = 0; ack_now = 0; replaying = 0; hold_ack = 0; hold_seen = 0;
      rb_head = 0; rb_tail = 0; tq_head = 0; tq_tail = 0;
      cons_ph = 0; cons_pd = 0; cons_nph = 0; cons_npd = 0;
      alloc_ph = 8; alloc_pd = 32; alloc_nph = 4; alloc_npd = 4;
      recv_ph = 0; recv_pd = 0; recv_nph = 0; recv_npd = 0;
      ack_t = 0; upd_t = -1; upd_np_t = -1; upd_p_t = -1; init_t = 0; upd_root_np_t = 0;
    end
  endtask

  task reset_tl;
    integer i;
    begin
      for (i = 0; i < 16; i = i + 1) cfg[i] = 0;
      cfg[0] = {DEVICE, VENDOR};
      cfg[2] = 32'hFF00_0001;                 // class code FF0000h, revision 1
      cfg[1] = 32'h0010_0000;                 // status: capabilities list
      rrs_left = rrs_init; ur_wait = 0; up_done = 0;
    end
  endtask

  initial begin reset_dll; reset_tl; end

  // ---------------- LTSSM ----------------
  task go(input integer s);
    begin
      lt = s; lt_t = 0; rx_cnt = 0; ts_tx = 0; ts_tx_after = 0; rx_seen = 0; rx_ok = 0; idle_rx = 0; idle_tx_after = 0;
      if (s == DQ || s == HR) begin
        if (link_up && s == HR) $display("PCIE DEV: hot reset at %0t ns", $time);
        link_up = 0; reset_dll;
        if (s == HR) reset_tl;
      end
      if (s == CI) link_up = 1;
      if (s == CNW) cnw_lane = last_lane;
    end
  endtask

  // a training set was received: count consecutive identical ones and apply the receive-side rules
  task ts_rx(input [7:0] id, input lpad, input [7:0] link, input wpad, input [7:0] lane, input [7:0] rate,
             input [7:0] ctrl);
    begin
      if (rate != 8'h02) violation("root advertises a data rate other than 2.5 GT/s");
      if (!lpad && link != 0) violation("root uses a link number other than 0");
      if (!wpad && lane != 0) violation("root uses a lane number other than 0");
      if (ctrl & 8'hFE) violation("root sets training control bits other than Hot Reset");
      if (rx_cnt > 0 && id == last_id && lpad == last_link_pad && link == last_link && wpad == last_lane_pad &&
          lane == last_lane && ctrl == last_ctrl) rx_cnt = rx_cnt + 1;
      else rx_cnt = 1;
      last_id = id; last_link_pad = lpad; last_link = link; last_lane_pad = wpad; last_lane = lane; last_ctrl = ctrl;
      // eight consecutive received is an event of the state; the transition also waits for sets sent
      case (lt)
        PA: if (lpad && wpad && rx_cnt >= 8) rx_ok = 1;
        PC: begin
          if (id == TS2 && lpad && wpad) rx_seen = 1;
          if (id == TS2 && lpad && wpad && rx_cnt >= 8) rx_ok = 1;
        end
        CC, RC: begin
          if (id == TS2) rx_seen = 1;
          if (id == TS2 && !lpad && link == link_num && !wpad && lane == lane_num && rx_cnt >= 8) rx_ok = 1;
        end
        default: ;
      endcase
      ts_go;
      case (lt)
        CLS: if (id == TS1 && !lpad && wpad && rx_cnt >= 2) begin link_num = link; go(CLA); end
        CLA: if (id == TS1 && !lpad && link == link_num && !wpad && rx_cnt >= 2) begin lane_num = lane; go(CNW); end
        CNW: if (rx_cnt >= 2 && (id == TS2 || (!wpad && lane != cnw_lane))) go(CNA);
        CNA: if (id == TS2 && !lpad && link == link_num && !wpad && lane == lane_num && rx_cnt >= 2) go(CC);
        L0: go(RL);
        RL: if (!lpad && link == link_num && !wpad && lane == lane_num && rx_cnt >= 8) go(RC);
        RI, CI: begin
          if (id == TS1 && ctrl[0] && rx_cnt >= 2) go(HR);
          else if (id == TS1 && wpad && rx_cnt >= 2) go(CLS);
        end
        HR: if (id == TS1 && ctrl[0] && rx_cnt >= 2) lt_t = 0;
        default: ;
      endcase
    end
  endtask

  task ts_go;
    case (lt)
      PA: if (rx_ok && ts_tx >= 1024) go(PC);
      PC: if (rx_ok && ts_tx_after >= 16) go(CLS);
      CC: if (rx_ok && ts_tx_after >= 16) go(CI);
      RC: if (rx_ok && ts_tx_after >= 16) go(RI);
      default: ;
    endcase
  endtask

  // ---------------- receive ----------------
  always @(posedge rx_idle) skp_rx = 0;
  always @(posedge rx_stb) if (perst_n && !rx_idle) begin : rx
    reg [7:0] s; reg k;
    s = rx_sym; k = rx_k;
    // a SKP ordered set at least every 1538 symbol times, plus the longest packet that can delay it
    skp_rx = skp_rx + 1;
    if (rx_mode == 1 && rx_n == 1 && k && s == SKP) skp_rx = 0;
    if (skp_rx == 1538 + 128 + 28 + 64 && lt != DQ) violation("no SKP ordered set from the root");
    if (rx_mode == 1) begin
      // ordered set in progress: a SKP ordered set is COM and one to five SKP
      if (rx_n == 1 && k && s == SKP) begin rxb[1] = SKP; rxk[1] = 1; rx_n = 2; end
      else if (rx_n >= 2 && rxk[1] && rxb[1] == SKP) begin
        if (k && s == SKP) rx_n = rx_n + 1;
        else begin rx_mode = 0; sym_rx(s, k); end
      end else if (k && s == COM) begin
        violation("ordered set cut short"); rx_mode = 0; sym_rx(s, k);
      end else begin
        rxb[rx_n] = s; rxk[rx_n] = k; rx_n = rx_n + 1;
        if (rx_n == 4 && rxk[1] && rxb[1] == IDL) begin
          rx_mode = 0;
          if (lt == L0) begin $display("PCIE DEV: EIOS in L0 at %0t ns", $time); go(RL); end
        end else if (rx_n == 4 && rxk[1] && rxb[1] == FTS) rx_mode = 0;
        else if (rx_n == 16) begin rx_mode = 0; os_done; end
      end
    end else if (rx_mode == 2) begin
      if (rx_n > 4100) begin violation("packet longer than 4100 symbols"); rx_mode = 0; end
      else begin
        rxb[rx_n] = s; rxk[rx_n] = k; rx_n = rx_n + 1;
        if (k && (s == END || s == EDB)) begin rx_mode = 0; pkt_done; end
        else if (k) begin violation("K symbol inside a packet"); rx_mode = 0; end
      end
    end else sym_rx(s, k);
  end

  task sym_rx(input [7:0] s, input k);
    begin
      if (k && s == COM) begin rx_mode = 1; rxb[0] = s; rxk[0] = 1; rxb[1] = 8'h00; rxk[1] = 0; rx_n = 1; end
      else if (k && (s == STP || s == SDP)) begin rx_mode = 2; rxb[0] = s; rxk[0] = 1; rx_n = 1; end
      else if (!k && s == 8'h00) begin
        idle_rx = idle_rx + 1;
        if ((lt == CI || lt == RI) && idle_rx >= 8 && idle_tx_after >= 16) go(L0);
      end else if (lt == L0 || lt == CI || lt == RI)
        violation("symbol other than logical idle between packets");
    end
  endtask

  task os_done;
    integer i; reg ok;
    begin
      ok = 1;
      for (i = 7; i < 16; i = i + 1) if (rxb[i] != rxb[6] || rxk[i]) ok = 0;
      if (rxk[3] || rxk[4] || rxk[5] || (rxb[6] != TS1 && rxb[6] != TS2)) ok = 0;
      if ((rxk[1] && rxb[1] != PAD) || (rxk[2] && rxb[2] != PAD)) ok = 0;
      if (!ok) violation("malformed training set");
      else ts_rx(rxb[6], rxk[1], rxb[1], rxk[2], rxb[2], rxb[4], rxb[5]);
    end
  endtask

  // ---------------- data link layer receive ----------------
  task pkt_done;
    reg [15:0] c; reg [31:0] l, lc; reg [11:0] seq; integer n;
    begin
      idle_rx = 0;
      if (lt != L0 && lt != CI && lt != RI && lt != RL) violation("packet outside L0");
      if (rxb[0] == SDP) begin
        if (rx_n != 8) violation("DLLP framing");
        else begin
          c = dcrc(rxb[1], rxb[2], rxb[3], rxb[4]);
          if (c != {rxb[5], rxb[6]}) violation("DLLP CRC");
          else dllp_rx(rxb[1], rxb[2], rxb[3], rxb[4]);
        end
      end else begin
        n = rx_n - 8;                                   // header, data and digest bytes
        seq = {rxb[1][3:0], rxb[2]};
        l = {rxb[rx_n - 5], rxb[rx_n - 4], rxb[rx_n - 3], rxb[rx_n - 2]};
        lc = lcrc(1, rx_n - 6, 0);
        if (rxb[rx_n - 1] == EDB) begin
          if (l != ~lc) violation("nullified TLP without the inverted LCRC");
        end else if (rxb[1][7:4] != 0) violation("TLP reserved bits");
        else if (n < 12 || n % 4) violation("TLP length is not whole DWs");
        else if (l != lc) begin
          violation("TLP LCRC");
          if (!nak_sched) begin nak_sched = 1; end
        end else if (seq == next_rcv_seq[11:0]) begin
          rx_tlps = rx_tlps + 1;
          if (nak_at != 0 && rx_tlps == nak_at) begin
            $display("PCIE DEV: Nak for TLP %0d at %0t ns", rx_tlps, $time);
            nak_sched = 1; nak_at = 0; rx_tlps = rx_tlps - 1;
          end else begin
            if (dl == 2) fi2 = 1;
            next_rcv_seq = (next_rcv_seq + 1) % 4096; nak_sched = 0;
            if (hold_ack_at != 0 && rx_tlps == hold_ack_at) begin hold_ack = 1; hold_seen = 0; end
            else ack_pend = 1;
            tlp_rx(n);
            if (recovery_at != 0 && rx_tlps == recovery_at) begin
              $display("PCIE DEV: entering Recovery at %0t ns", $time); recovery_at = 0; go(RL);
            end
          end
        end else if (((next_rcv_seq - seq) & 4095) <= 2048) begin
          if (hold_ack) begin hold_ack = 0; $display("PCIE DEV: replay of the held TLP at %0t ns", $time); end
          ack_now = 1;                                    // duplicate
        end else begin
          violation("TLP sequence number out of order");
          nak_sched = 1;
        end
      end
    end
  endtask

  task dllp_rx(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3);
    reg [11:0] s; integer hdr, dat;
    begin
      hdr = {b1[5:0], b2[7:6]}; dat = {b2[3:0], b3};
      case (b0[7:4])
        4'h0, 4'h1: begin
          s = {b2[3:0], b3};
          if (dl != 3) violation("Ack or Nak before DL_Active");
          else if (s == ackd_seq[11:0]) begin if (b0[4]) replay; end
          else if (((s - ackd_seq) & 4095) < 2048 && (((next_tx_seq - 1) - s) & 4095) <= 2048) begin
            while (rb_head != rb_tail && ((s - rb_seq[rb_head % 16]) & 4095) < 2048) rb_head = rb_head + 1;
            ackd_seq = s; replay_num = 0;
            replay_t = rb_head != rb_tail ? 0 : -1;
            if (b0[4]) replay;
          end else violation("Ack or Nak with a sequence number not outstanding");
        end
        4'h4, 4'h5, 4'h6, 4'hC, 4'hD, 4'hE: begin
          if (b0[3:0] != 0) violation("flow control DLLP for a VC other than 0");
          if (b1[7:6] != 0 || b2[5:4] != 0) violation("scaled flow control from the root");
          if (dl == 1 && !b0[7]) begin
            case (b0[5:4])
              2'b00: begin root_ph = hdr ? hdr : -1; root_pd = dat ? dat : -1; fi1[0] = 1; end
              2'b01: begin root_nph = hdr ? hdr : -1; root_npd = dat ? dat : -1; fi1[1] = 1; end
              default: begin root_cplh = hdr ? hdr : -1; root_cpld = dat ? dat : -1; fi1[2] = 1; end
            endcase
          end
          if (dl == 2 && b0[7]) fi2 = 1;
        end
        4'h8, 4'h9, 4'hA: begin
          if (dl == 2) fi2 = 1;
          if (dl < 2) violation("UpdateFC before FC_INIT2");
          case (b0[5:4])
            2'b00: begin
              if (root_ph >= 0) root_ph = hdr; else if (hdr) violation("UpdateFC-P with credits after infinite");
              if (root_pd >= 0) root_pd = dat; else if (dat) violation("UpdateFC-P with credits after infinite");
            end
            2'b01: begin
              upd_root_np_t = 0;
              if (root_nph >= 0) root_nph = hdr; else if (hdr) violation("UpdateFC-NP with credits after infinite");
              if (root_npd >= 0) root_npd = dat; else if (dat) violation("UpdateFC-NP with credits after infinite");
            end
            default: if (hdr || dat) violation("UpdateFC-Cpl with credits after infinite");
          endcase
        end
        4'h0, 4'h2, 4'h3: ;
        default: violation("DLLP type the root should not send");
      endcase
    end
  endtask

  task replay;
    begin
      if (rb_head != rb_tail) begin
        replay_num = replay_num + 1;
        replaying = 1; rb_replay = rb_head; replay_t = -1;
      end
    end
  endtask

  // ---------------- transaction layer ----------------
  // TLP bytes in rxb[3 ..]; n bytes of header, data and digest
  task tlp_rx(input integer n);
    reg [7:0] t; reg [9:0] len; reg [31:0] a, d; reg [3:0] fbe, lbe; reg [15:0] rid; reg [7:0] tag;
    integer h, nd, i, r; reg [2:0] st;
    begin
      t = rxb[3]; len = {rxb[5][1:0], rxb[6]};
      h = t[5] ? 16 : 12;
      nd = t[6] ? (len == 0 ? 4096 : len * 4) : 0;
      if (n != h + nd + (rxb[5][7] ? 4 : 0)) violation("TLP length field and size differ");
      if (rxb[4][6:4] != 0) violation("TLP with a traffic class other than 0");
      if (rxb[5][7]) violation("TLP with a digest");
      if (rxb[5][6]) violation("poisoned TLP");
      rid = {rxb[7], rxb[8]}; tag = rxb[9]; lbe = rxb[10][7:4]; fbe = rxb[10][3:0];
      // credits consumed
      if (t == 8'h40 || t == 8'h60 || t[7:3] == 5'b00110 || t[7:3] == 5'b01110) begin
        recv_ph = recv_ph + 1; recv_pd = recv_pd + (nd + 15) / 16;
        if (recv_ph > alloc_ph || recv_pd > alloc_pd) violation("root exceeds Posted credits");
        alloc_ph = alloc_ph + 1; alloc_pd = alloc_pd + (nd + 15) / 16; if (upd_p_t < 0) upd_p_t = 0;
      end else if (t != 8'h0A && t != 8'h4A) begin
        recv_nph = recv_nph + 1; recv_npd = recv_npd + (nd + 15) / 16;
        if (recv_nph > alloc_nph || recv_npd > alloc_npd) violation("root exceeds Non-Posted credits");
        alloc_nph = alloc_nph + 1; alloc_npd = alloc_npd + (nd + 15) / 16; if (upd_np_t < 0) upd_np_t = 0;
      end
      if (t == 8'h04 || t == 8'h44) begin
        // configuration, Type 0
        if (len != 1 || lbe != 0 || rxb[5][5:4] != 0 || rxb[4][2] || rid != 0)
          violation("configuration request fields");
        r = rxb[14][7:2] | (rxb[13][3:0] << 6);
        if (rxb[12][2:0] != 0) cpl(rid, tag, 3'b001, 0, 4, 0, 0);
        else if (rrs_left > 0) begin rrs_left = rrs_left - 1; cpl(rid, tag, 3'b010, 0, 4, 0, 0); end
        else if (t == 8'h04) cpl(rid, tag, 3'b000, 1, 4, 0, r < 16 ? cfg[r] : 32'h0);
        else begin
          my_id = {rxb[11], rxb[12][7:3], 3'b000};
          d = {rxb[18], rxb[17], rxb[16], rxb[15]};
          if (r == 1) for (i = 0; i < 2; i = i + 1) if (fbe[i]) cfg[1][i * 8 +: 8] = d[i * 8 +: 8] & (i ? 8'h00 : 8'h06);
          if (r == 4) for (i = 0; i < 4; i = i + 1) if (fbe[i]) cfg[4][i * 8 +: 8] = d[i * 8 +: 8] & (i == 0 ? 8'h00 : i == 1 ? 8'hF0 : 8'hFF);
          if (r == 15) if (fbe[0]) cfg[15][7:0] = d[7:0];
          cpl(rid, tag, 3'b000, 0, 4, 0, 0);
          if (r == 1 && cfg[1][2] && up_req && !up_done) begin up_done = 1; send_up_req; end
        end
      end else if (t == 8'h00 || t == 8'h40) begin
        a = {rxb[11], rxb[12], rxb[13], rxb[14][7:2], 2'b00};
        if (len != 1 || lbe != 0 || rxb[14][1:0] != 0 || rid != 0) violation("memory request fields");
        if (cfg[1][1] && a[31:12] == cfg[4][31:12]) begin
          if (t == 8'h00) cpl(rid, tag, 3'b000, 1, bytes(fbe), {a[6:2], la(fbe)}, mem[a[9:2]]);
          else begin
            d = {rxb[18], rxb[17], rxb[16], rxb[15]};
            for (i = 0; i < 4; i = i + 1) if (fbe[i]) mem[a[9:2]][i * 8 +: 8] = d[i * 8 +: 8];
          end
        end else if (t == 8'h00) cpl(rid, tag, 3'b001, 0, bytes(fbe), {a[6:2], la(fbe)}, 0);
        else violation("memory write outside the BAR or with memory space disabled");
      end else if (t == 8'h0A || t == 8'h4A) begin
        // completion of a request this device sent
        st = rxb[9][7:5];
        if (!ur_wait) violation("unexpected completion");
        else if (t != 8'h0A || st != 3'b001 || {rxb[11], rxb[12]} != my_id || rxb[13] != up_tag ||
                 {rxb[9][3:0], rxb[10]} != 4 || rxb[14][6:0] != 7'h00) begin
          violation("root's UR completion fields");
          $display("  completion %h %h %h %h  %h %h %h %h  %h %h %h %h, requester %h tag %h", rxb[3], rxb[4], rxb[5],
                   rxb[6], rxb[7], rxb[8], rxb[9], rxb[10], rxb[11], rxb[12], rxb[13], rxb[14], my_id, up_tag);
        end
        else begin $display("PCIE DEV: UR completion from the root at %0t ns", $time); ur_wait = 0; end
      end else violation("TLP type the root should not send");
    end
  endtask

  function [11:0] bytes(input [3:0] be);
    bytes = be[0] && be[3] ? 4 : (be[1] && be[3]) || (be[0] && be[2]) ? 3 :
            be == 4'b0011 || be == 4'b0110 || be == 4'b1100 ? 2 : 1;
  endfunction
  function [1:0] la(input [3:0] be);
    la = be[0] ? 2'd0 : be[1] ? 2'd1 : be[2] ? 2'd2 : be[3] ? 2'd3 : 2'd0;
  endfunction

  // queue a completion
  task cpl(input [15:0] rid, input [7:0] tag, input [2:0] st, input withdata, input [11:0] bc, input [6:0] lad,
           input [31:0] d);
    integer b;
    begin
      b = (tq_tail % 16) * 128;
      tq[b] = withdata ? 8'h4A : 8'h0A; tq[b + 1] = 0; tq[b + 2] = 0; tq[b + 3] = withdata ? 8'h01 : 8'h00;
      tq[b + 4] = my_id[15:8]; tq[b + 5] = my_id[7:0]; tq[b + 6] = {st, 1'b0, bc[11:8]}; tq[b + 7] = bc[7:0];
      tq[b + 8] = rid[15:8]; tq[b + 9] = rid[7:0]; tq[b + 10] = tag; tq[b + 11] = {1'b0, lad};
      if (withdata) begin tq[b + 12] = d[7:0]; tq[b + 13] = d[15:8]; tq[b + 14] = d[23:16]; tq[b + 15] = d[31:24]; end
      tq_len[tq_tail % 16] = withdata ? 16 : 12; tq_type[tq_tail % 16] = 2;
      tq_tail = tq_tail + 1;
    end
  endtask

  // MRd32, MWr32 and Assert_INTA towards the root
  task send_up_req;
    integer b;
    begin
      b = (tq_tail % 16) * 128;
      tq[b] = 8'h00; tq[b + 1] = 0; tq[b + 2] = 0; tq[b + 3] = 1; tq[b + 4] = my_id[15:8]; tq[b + 5] = my_id[7:0];
      tq[b + 6] = up_tag; tq[b + 7] = 8'h0F; tq[b + 8] = 0; tq[b + 9] = 0; tq[b + 10] = 8'h10; tq[b + 11] = 0;
      tq_len[tq_tail % 16] = 12; tq_type[tq_tail % 16] = 1; tq_tail = tq_tail + 1;
      b = (tq_tail % 16) * 128;
      tq[b] = 8'h40; tq[b + 1] = 0; tq[b + 2] = 0; tq[b + 3] = 1; tq[b + 4] = my_id[15:8]; tq[b + 5] = my_id[7:0];
      tq[b + 6] = 0; tq[b + 7] = 8'h0F; tq[b + 8] = 0; tq[b + 9] = 0; tq[b + 10] = 8'h10; tq[b + 11] = 8'h04;
      tq[b + 12] = 8'h11; tq[b + 13] = 8'h22; tq[b + 14] = 8'h33; tq[b + 15] = 8'h44;
      tq_len[tq_tail % 16] = 16; tq_type[tq_tail % 16] = 0; tq_tail = tq_tail + 1;
      b = (tq_tail % 16) * 128;
      tq[b] = 8'h34; tq[b + 1] = 0; tq[b + 2] = 0; tq[b + 3] = 0; tq[b + 4] = my_id[15:8]; tq[b + 5] = my_id[7:0];
      tq[b + 6] = 0; tq[b + 7] = 8'h20; tq[b + 8] = 0; tq[b + 9] = 0; tq[b + 10] = 0; tq[b + 11] = 0;
      tq[b + 12] = 0; tq[b + 13] = 0; tq[b + 14] = 0; tq[b + 15] = 0;
      tq_len[tq_tail % 16] = 16; tq_type[tq_tail % 16] = 0; tq_tail = tq_tail + 1;
      ur_wait = 1;
    end
  endtask

  // ---------------- transmit ----------------
  task put(input [7:0] s, input k); begin txb[tx_len] = s; txk[tx_len] = k; tx_len = tx_len + 1; end endtask

  task ts(input [7:0] id, input [7:0] ctrl);
    integer i;
    begin
      tx_len = 0; tx_pos = 0;
      put(COM, 1);
      if (lt == CLA || lt == CNW || lt == CNA || lt == CC || lt == RL || lt == RC || lt == HR) put(link_num, 0);
      else put(PAD, 1);
      if (lt == CNW || lt == CNA || lt == CC || lt == RL || lt == RC || lt == HR) put(lane_num, 0);
      else put(PAD, 1);
      put(8'd23, 0); put(8'h02, 0); put(ctrl, 0);
      for (i = 6; i < 16; i = i + 1) put(id, 0);
      ts_tx = ts_tx + 1;
      if (rx_seen) ts_tx_after = ts_tx_after + 1;
      ts_go;
    end
  endtask

  task dllp(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3);
    reg [15:0] c;
    begin
      tx_len = 0; tx_pos = 0; c = dcrc(b0, b1, b2, b3);
      put(SDP, 1); put(b0, 0); put(b1, 0); put(b2, 0); put(b3, 0); put(c[15:8], 0); put(c[7:0], 0); put(END, 1);
    end
  endtask

  task fc(input [7:0] b0, input integer hdr, input integer dat);
    begin dllp(b0, {2'b00, hdr[7:2]}, {hdr[1:0], 2'b00, dat[11:8]}, dat[7:0]); end
  endtask

  // credits a queued TLP needs; 1 if the root's limits allow it
  function fits(input integer i);
    integer h, d;
    begin
      d = tq[i * 128][6] ? 1 : 0;
      if (tq_type[i] == 2) fits = 1;
      else if (tq_type[i] == 0)
        fits = (root_ph < 0 || ((root_ph - (cons_ph + 1)) & 255) <= 128) &&
               (root_pd < 0 || ((root_pd - (cons_pd + d)) & 4095) <= 2048);
      else fits = (root_nph < 0 || ((root_nph - (cons_nph + 1)) & 255) <= 128) &&
                  (root_npd < 0 || ((root_npd - (cons_npd + d)) & 4095) <= 2048);
    end
  endfunction

  // move a queued TLP into the retry buffer
  task frame_tlp;
    integer i, b, n, e; reg [31:0] c;
    begin
      i = tq_head % 16; b = i * 128; n = tq_len[i];
      if (tq_type[i] == 0) begin cons_ph = (cons_ph + 1) & 255; if (tq[b][6]) cons_pd = (cons_pd + 1) & 4095; end
      if (tq_type[i] == 1) begin cons_nph = (cons_nph + 1) & 255; if (tq[b][6]) cons_npd = (cons_npd + 1) & 4095; end
      e = 4096 + (rb_tail % 16) * 64;
      txb[e] = STP; txb[e + 1] = {4'b0, next_tx_seq[11:8]}; txb[e + 2] = next_tx_seq[7:0];
      for (b = 0; b < n; b = b + 1) txb[e + 3 + b] = tq[i * 128 + b];
      c = lcrc(e + 1, n + 2, 1);
      tx_tlps = tx_tlps + 1;
      txb[e + 3 + n] = c[31:24]; txb[e + 4 + n] = c[23:16]; txb[e + 5 + n] = c[15:8]; txb[e + 6 + n] = c[7:0];
      txb[e + 7 + n] = END;
      rb_len[rb_tail % 16] = n + 8; rb_seq[rb_tail % 16] = next_tx_seq[11:0];
      rb_tail = rb_tail + 1; tq_head = tq_head + 1; next_tx_seq = (next_tx_seq + 1) % 4096;
    end
  endtask

  task send_rb(input integer j, input first);
    integer e, i;
    begin
      e = 4096 + (j % 16) * 64; tx_len = 0; tx_pos = 0;
      for (i = 0; i < rb_len[j % 16]; i = i + 1) put(txb[e + i], i == 0 || i == rb_len[j % 16] - 1);
      // the first transmission of the chosen TLP goes out with one LCRC bit flipped
      if (first && lcrc_err_at != 0 && tx_tlps == lcrc_err_at) begin
        txb[tx_len - 3] = txb[tx_len - 3] ^ 8'h01; lcrc_err_at = 0;
        $display("PCIE DEV: bad LCRC on TLP %0d at %0t ns", tx_tlps, $time);
      end
      if (replay_t < 0) replay_t = 0;
    end
  endtask

  always @(negedge clk) begin : tx
    if (!perst_n) begin
      tx_idle = 1; tx_len = 0; tx_pos = 0; was_active = 0;
      if (lt != DQ) go(DQ);
      lt_t = 0;
    end else begin
      lt_t = lt_t + 1;
      timeouts;
      if (tx_pos >= tx_len) begin
        // next item
        tx_len = 0; tx_pos = 0;
        if (lt == DQ) begin
          if (was_active) begin put(COM, 1); put(IDL, 1); put(IDL, 1); put(IDL, 1); was_active = 0; end
        end else if (skp_t >= 1200) begin
          put(COM, 1); put(SKP, 1); put(SKP, 1); put(SKP, 1); skp_t = 0;
        end else case (lt)
          PA, CLS, CLA, CNW, CNA, RL: ts(TS1, 0);
          PC, CC, RC: ts(TS2, 0);
          HR: ts(TS1, 1);
          CI, RI: begin
            put(8'h00, 0); put(8'h00, 0); put(8'h00, 0); put(8'h00, 0);
            if (idle_rx > 0) idle_tx_after = idle_tx_after + 4;
            if (idle_rx >= 8 && idle_tx_after >= 16) go(L0);
          end
          L0: dl_tx;
          default: ;
        endcase
      end
      if (tx_pos < tx_len) begin
        tx_idle = 0; was_active = 1;
        tx_sym = txb[tx_pos]; tx_k = txk[tx_pos]; tx_pos = tx_pos + 1;
        skp_t = skp_t + 1;
      end else begin
        tx_idle = lt == DQ; tx_sym = 0; tx_k = 0;
        if (lt == DQ) skp_t = 0;
      end
      dl_timers;
    end
  end

  // ---------------- timeouts ----------------
  task timeouts;
    begin
      case (lt)
        DQ: if (lt_t > 400) go(PA);                                 // receiver assumed present
        PA: if (lt_t > ms(24)) go(DQ);
        PC: if (lt_t > ms(48)) go(DQ);
        CLS, RL: if (lt_t > ms(24)) go(DQ);
        CLA, CNW, CNA, CC, CI, RI: if (lt_t > ms(2)) go(DQ);
        RC: if (lt_t > ms(48)) go(DQ);
        HR: if (lt_t > ms(2)) go(DQ);
        default: ;
      endcase
    end
  endtask

  // ---------------- data link layer transmit ----------------
  task dl_tx;
    begin
      if (dl == 0) begin dl = 1; fi1 = 0; end
      if (dl == 1 && fi1 == 3'b111) begin dl = 2; fi2 = 0; end
      if (dl == 2 && fi2) begin dl = 3; $display("PCIE DEV: DL_Active at %0t ns", $time); end
      if (nak_sched && !ack_now && dl == 3) begin
        dllp(8'h10, 0, {4'b0, next_rcv_seq_m1[11:8]}, next_rcv_seq_m1[7:0]); nak_sched = 0;
        $display("PCIE DEV: Nak sent at %0t ns", $time);
      end else if ((ack_now || (ack_pend && ack_t > 100)) && !hold_ack && dl == 3) begin
        dllp(8'h00, 0, {4'b0, next_rcv_seq_m1[11:8]}, next_rcv_seq_m1[7:0]); ack_now = 0; ack_pend = 0; ack_t = 0;
      end else if (dl == 3 && upd_np_t > 60) begin fc(8'h90, alloc_nph & 255, alloc_npd & 4095); upd_np_t = -1; end
      else if (dl == 3 && upd_p_t > 60) begin fc(8'h80, alloc_ph & 255, alloc_pd & 4095); upd_p_t = -1; end
      else if (dl == 3 && upd_t > 7000) begin fc(8'h80, alloc_ph & 255, alloc_pd & 4095); upd_t = 0; upd_np_t = 50; end
      else if (dl == 3 && replaying) begin
        send_rb(rb_replay, 1'b0); rb_replay = rb_replay + 1;
        if (rb_replay == rb_tail) replaying = 0;
      end else if (dl == 3 && rb_tail - rb_head < 8 && tq_head != tq_tail && fits(tq_head % 16)) begin
        frame_tlp; send_rb(rb_tail - 1, 1'b1);
      end else if (dl == 1 || dl == 2) begin
        case (init_t % 3)
          0: fc(dl == 1 ? 8'h40 : 8'hC0, 8, 32);
          1: fc(dl == 1 ? 8'h50 : 8'hD0, 4, 4);
          default: fc(dl == 1 ? 8'h60 : 8'hE0, 0, 0);
        endcase
        init_t = init_t + 1;
      end else begin put(8'h00, 0); put(8'h00, 0); put(8'h00, 0); put(8'h00, 0); end
    end
  endtask

  task dl_timers;
    begin
      if (dl == 3) begin
        if (ack_pend) ack_t = ack_t + 1;
        if (upd_np_t >= 0) upd_np_t = upd_np_t + 1;
        if (upd_p_t >= 0) upd_p_t = upd_p_t + 1;
        if (upd_t >= 0) upd_t = upd_t + 1; else upd_t = 0;
        if (replay_t >= 0) begin
          replay_t = replay_t + 1;
          if (replay_t > 26000) begin $display("PCIE DEV: replay timer at %0t ns", $time); replay; end
        end
        // the root advertised finite Non-Posted credits, so it has to update them at least every 30 us (+50%)
        upd_root_np_t = upd_root_np_t + 1;
        if (lt == L0 && root_nph >= 0 && upd_root_np_t > 11250) begin
          violation("no UpdateFC-NP from the root for 45 us"); upd_root_np_t = 0;
        end
        if (ur_wait) begin
          ur_wait = ur_wait + 1;
          if (ur_wait > 250000) begin violation("no completion for the device's MRd"); ur_wait = 0; end
        end
      end
      if (lt != L0) upd_root_np_t = 0;
    end
  endtask
endmodule
