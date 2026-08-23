// PCIe Gen1 x4 link above a 32-bit PIPE interface (one 16-symbol block per PCLK).
// Reduced LTSSM (Detect, Polling, Configuration, L0), byte striping, STP/SDP/END framing,
// data link layer with sequence numbers, LCRC, Ack/Nak, a one-TLP retry buffer and InitFC.
// Packets start on block boundaries. Scrambling is disabled through the TS training control field.
module pcie_mac #(parameter ROOT = 1) (
  input              clk,
  input              rst,
  // PIPE
  output reg [127:0] tx_data,
  output reg  [15:0] tx_datak,
  output reg         tx_elecidle,
  output reg         tx_detect_rx,
  output       [1:0] power_down,
  input      [127:0] rx_data,
  input       [15:0] rx_datak,
  input        [3:0] rx_elecidle,
  input       [11:0] rx_status,
  input              phy_status,
  // transaction layer: one TLP of 12 or 16 bytes, byte 0 in [7:0]
  input              t_valid,
  input              t_len16,
  input      [127:0] t_data,
  output             t_ready,
  output reg         t_done,      // the partner acknowledged the TLP
  output reg         r_valid,
  output reg [127:0] r_data,
  // status
  output             link_up,
  output reg   [2:0] ltssm,
  output reg   [7:0] replays
);
  localparam [7:0] COM = 8'hBC, SKP = 8'h1C, STP = 8'hFB, SDP = 8'h5C, END = 8'hFD, PAD = 8'hF7,
                   TS1 = 8'h4A, TS2 = 8'h45;
  localparam [2:0] S_DQ = 0, S_DA = 1, S_PA = 2, S_PC = 3, S_CL = 4, S_CC = 5, S_L0 = 6;
  localparam [1:0] FC1 = 0, FC2 = 1, FCA = 2;
  localparam [11:0] DETECTED = {4{3'b011}};

  assign power_down = ltssm == S_DQ || ltssm == S_DA ? 2'b10 : 2'b00;   // P1 while detecting

  function [31:0] crc32_byte(input [31:0] c, input [7:0] d);   // reflected CRC-32, poly 04C11DB7
    integer n; reg [31:0] x;
    begin
      x = c ^ {24'b0, d};
      for (n = 0; n < 8; n = n + 1) x = x[0] ? (x >> 1) ^ 32'hEDB88320 : x >> 1;
      crc32_byte = x;
    end
  endfunction

  function [15:0] crc16(input [31:0] d);                         // reflected CRC-16, poly 100B
    integer n; reg [15:0] x;
    begin
      x = 16'hFFFF;
      for (n = 0; n < 32; n = n + 1) x = x[0] ^ d[n] ? (x >> 1) ^ 16'hD008 : x >> 1;
      crc16 = ~x;
    end
  endfunction

  // PIPE receive inputs: captured on the falling edge, then on the rising edge
  reg  [160:0] rx_n, rx_r;
  always @(negedge clk) rx_n <= {rx_data, rx_datak, rx_elecidle, rx_status, phy_status};
  always @(posedge clk) rx_r <= rx_n;
  wire [127:0] rxd    = rx_r[160:33];
  wire  [15:0] rxk    = rx_r[32:17];
  wire   [3:0] rx_ei  = rx_r[16:13];
  wire  [11:0] rx_st  = rx_r[12:1];
  wire         phy_st = rx_r[0];

  // receive block as a stream of 16 symbols: symbol k on lane k%4, slot k/4
  reg [7:0] rs [0:15];
  reg       rk [0:15];
  integer   k;
  always @* for (k = 0; k < 16; k = k + 1) begin
    rs[k] = rxd[(k % 4) * 32 + (k / 4) * 8 +: 8];
    rk[k] = rxk[(k % 4) * 4 + k / 4];
  end

  // ---------------- state ----------------
  reg  [10:0] ts_tx;        // ordered sets sent in this state
  reg   [3:0] ts_rx;        // consecutive matching ordered sets received
  reg         rx_ok;        // eight matching ordered sets seen
  reg   [4:0] ts_after;     // sent since the first match
  reg         seen;         // first match seen
  reg         numbered;     // TS carry link and lane numbers
  reg   [1:0] os_q;         // quarter of the ordered set being sent
  reg   [6:0] timer;

  reg   [1:0] fc;
  reg   [2:0] fc1_seen;
  reg   [1:0] fc_idx, fc2_sent;
  reg         fc2_rx;
  assign link_up = ltssm == S_L0 && fc == FCA;

  reg  [11:0] tx_seq, rx_seq, ack_seq;
  reg         ack_pend, nak_pend;

  // retry buffer: one framed TLP of 32 symbols, in stream order
  reg [255:0] rb_d;
  reg  [31:0] rb_k;
  reg         rb_valid, rb_send, building, len16;
  reg  [11:0] rb_seq;
  reg  [10:0] replay_t;
  reg [127:0] t_hold;
  reg [143:0] crc_in;       // sequence number (2 bytes) and TLP
  reg   [4:0] crc_n;
  reg  [31:0] crc;
  wire  [4:0] crc_len = len16 ? 5'd18 : 5'd14;
  wire        crc_last = building && crc_n + 1 == crc_len;
  wire [31:0] lcrc = ~crc32_byte(crc, crc_in[7:0]);
  assign t_ready = t_valid && link_up && !rb_valid && !building;

  // receive TLP buffer
  reg [255:0] rp_d;
  reg  [31:0] rp_k;
  reg   [1:0] rp_st;        // 0 idle, 1 second block, 2 checking
  reg   [4:0] rp_n;
  reg         rp_l16;       // 16-byte TLP
  reg  [31:0] rp_crc;
  wire        rp_good = rp_l16 ? ~rp_crc == rp_d[19 * 8 +: 32] && rp_k[23] && rp_d[23 * 8 +: 8] == END
                               : ~rp_crc == rp_d[15 * 8 +: 32] && rp_k[19] && rp_d[19 * 8 +: 8] == END;

  reg         tx_tlp2;      // the second block of a TLP is next
  reg   [8:0] skp_t;

  // ---------------- ordered set receive ----------------
  // quarter 0 carries COM, link and lane; quarter 1 the TS identifier
  reg     os_hold, os_link0, os_pad, os_ev, os_ts2;
  reg     lanes_ok, lanes_pad;
  integer la;
  wire    os_start = rk[0] && rs[0] == COM && !(rk[4] && rs[4] == SKP);
  always @* begin
    lanes_ok = 1'b1; lanes_pad = 1'b1;
    for (la = 0; la < 4; la = la + 1) begin
      lanes_ok  = lanes_ok  && !rxk[la * 4 + 2] && rxd[la * 32 + 16 +: 8] == la[7:0];
      lanes_pad = lanes_pad &&  rxk[la * 4 + 2] && rxd[la * 32 + 16 +: 8] == PAD;
    end
  end

  wire want_ts2 = ltssm == S_PC || ltssm == S_CC;
  wire match    = os_ev && (ltssm == S_PA ? os_pad :
                            ltssm == S_PC ? os_pad && os_ts2 :
                            ltssm == S_CL ? os_link0 && !os_ts2 && numbered :
                                            os_link0 && os_ts2);
  wire os_end   = os_q == 2'd3;

  // ---------------- transmit block ----------------
  reg  [127:0] nd;
  reg   [15:0] nk;
  reg          sent_tlp, sent_skp, sent_dllp;
  wire  [11:0] nak_seq = rx_seq - 12'd1;
  wire  [31:0] dllp = nak_pend ? {nak_seq[7:0], 4'b0, nak_seq[11:8], 8'h00, 8'h10} :
                      ack_pend ? {ack_seq[7:0], 4'b0, ack_seq[11:8], 8'h00, 8'h00} :
                                 {24'b0, (fc == FC1 ? 4'h4 : 4'hC) + {2'b0, fc_idx}, 4'h0};
  wire  [15:0] dllp_crc = crc16(dllp);
  integer ts, tl, tj;

  always @* begin
    nd = 128'b0; nk = 16'b0; tj = 0;
    sent_tlp = 1'b0; sent_skp = 1'b0; sent_dllp = 1'b0;
    if (ltssm >= S_PA && ltssm <= S_CC) begin
      for (ts = 0; ts < 4; ts = ts + 1)
        for (tl = 0; tl < 4; tl = tl + 1) begin
          tj = os_q * 4 + ts;
          nd[tl * 32 + ts * 8 +: 8] = tj == 0 ? COM : tj == 1 ? (numbered ? 8'd0 : PAD) :
                                      tj == 2 ? (numbered ? tl[7:0] : PAD) : tj == 3 ? 8'h10 :
                                      tj == 4 ? 8'h02 : tj == 5 ? 8'h08 : want_ts2 ? TS2 : TS1;
          nk[tl * 4 + ts] = tj == 0 || (tj <= 2 && !numbered);
        end
    end else if (ltssm == S_L0) begin
      if (tx_tlp2) begin
        for (ts = 0; ts < 16; ts = ts + 1) begin
          nd[(ts % 4) * 32 + (ts / 4) * 8 +: 8] = rb_d[128 + ts * 8 +: 8];
          nk[(ts % 4) * 4 + ts / 4] = rb_k[16 + ts];
        end
      end else if (skp_t >= 9'd320) begin
        sent_skp = 1'b1;
        nd = {4{SKP, SKP, SKP, COM}}; nk = 16'hFFFF;
      end else if (nak_pend || ack_pend || fc != FCA) begin
        sent_dllp = 1'b1;
        // stream symbols 0..7: SDP, DLLP bytes 0..3, CRC low, CRC high, END
        nd[7:0] = SDP; nk[0] = 1'b1;
        nd[39:32] = dllp[7:0];       nd[71:64] = dllp[15:8];   nd[103:96] = dllp[23:16];
        nd[15:8]  = dllp[31:24];     nd[47:40] = dllp_crc[7:0];
        nd[79:72] = dllp_crc[15:8];  nd[111:104] = END; nk[12 + 1] = 1'b1;
      end else if (rb_send) begin
        sent_tlp = 1'b1;
        for (ts = 0; ts < 16; ts = ts + 1) begin
          nd[(ts % 4) * 32 + (ts / 4) * 8 +: 8] = rb_d[ts * 8 +: 8];
          nk[(ts % 4) * 4 + ts / 4] = rb_k[ts];
        end
      end
    end
  end

  // ---------------- sequential ----------------
  integer i;
  always @(posedge clk) begin
    t_done  <= 1'b0;
    r_valid <= 1'b0;
    if (rst) begin
      ltssm <= S_DQ; timer <= 0; os_q <= 0; os_hold <= 1'b0; os_ev <= 1'b0;
      tx_elecidle <= 1'b1; tx_detect_rx <= 1'b0;
      tx_data <= 0; tx_datak <= 0;
      fc <= FC1; fc1_seen <= 0; fc_idx <= 0; fc2_sent <= 0; fc2_rx <= 1'b0;
      rb_valid <= 1'b0; rb_send <= 1'b0; building <= 1'b0; tx_tlp2 <= 1'b0;
      ack_pend <= 1'b0; nak_pend <= 1'b0; rp_st <= 0;
      tx_seq <= 0; rx_seq <= 0; replays <= 0; replay_t <= 0; skp_t <= 0;
    end else begin
      tx_data <= nd; tx_datak <= nk;

      // ordered set receive
      os_ev <= 1'b0;
      if (os_hold) begin
        os_hold <= 1'b0;
        os_ev   <= rs[8] == TS1 || rs[8] == TS2;    // symbol 6 of lane 0: quarter 1, slot 2
        os_ts2  <= rs[8] == TS2;
      end else if (os_start) begin
        os_hold  <= 1'b1;
        os_link0 <= !rk[4] && rs[4] == 8'd0 && lanes_ok;
        os_pad   <= rk[4] && rs[4] == PAD && lanes_pad;
      end

      // ordered set counters
      if (ltssm >= S_PA && ltssm <= S_CC) begin
        os_q <= os_q + 1;
        if (os_end) begin
          if (ts_tx != 11'h7FF) ts_tx <= ts_tx + 1;
          if (seen && ts_after != 5'h1F) ts_after <= ts_after + 1;
        end
      end
      if (os_ev) begin
        if (match) begin
          seen <= 1'b1;
          if (ts_rx != 4'hF) ts_rx <= ts_rx + 1;
          if (ts_rx >= 4'd7) rx_ok <= 1'b1;
        end else ts_rx <= 0;
        if (ltssm == S_CL && os_link0) numbered <= 1'b1;
      end

      // LTSSM
      case (ltssm)
        S_DQ: begin
          tx_elecidle <= 1'b1;
          if (!phy_st) timer <= timer + 1;
          if (&timer) begin ltssm <= S_DA; tx_detect_rx <= 1'b1; end
        end
        S_DA: if (phy_st) begin
          tx_detect_rx <= 1'b0;
          timer <= 0;
          ltssm <= rx_st == DETECTED ? S_PA : S_DQ;
          tx_elecidle <= rx_st != DETECTED;
          {ts_tx, ts_rx, rx_ok, ts_after, seen, numbered, os_q} <= 0;
        end
        S_PA: if (rx_ok && ts_tx >= 11'd1024 && os_end) begin
          ltssm <= S_PC; {ts_rx, rx_ok, ts_after, seen} <= 0;
        end
        S_PC: if (rx_ok && ts_after >= 5'd16 && os_end) begin
          ltssm <= S_CL; {ts_rx, rx_ok, ts_after, seen} <= 0; numbered <= ROOT != 0;
        end
        S_CL: if (ts_rx >= 4'd2 && numbered && os_end) begin
          ltssm <= S_CC; {ts_rx, rx_ok, ts_after, seen} <= 0;
        end
        S_CC: if (rx_ok && ts_after >= 5'd16 && os_end) ltssm <= S_L0;
        default: if (&rx_ei) ltssm <= S_DQ;
      endcase

      // transmit bookkeeping
      skp_t   <= ltssm != S_L0 || sent_skp ? 9'd0 : skp_t + 1;
      tx_tlp2 <= sent_tlp;
      if (sent_tlp) begin rb_send <= 1'b0; replay_t <= 0; end
      else if (rb_valid && !rb_send) begin
        replay_t <= replay_t + 1;
        if (&replay_t) begin rb_send <= 1'b1; replays <= replays + 1; end
      end
      if (sent_dllp) begin
        if (nak_pend) nak_pend <= 1'b0;
        else if (ack_pend) ack_pend <= 1'b0;
        else begin
          fc_idx <= fc_idx == 2'd2 ? 2'd0 : fc_idx + 1;
          if (fc == FC2 && fc2_sent != 2'd3) fc2_sent <= fc2_sent + 1;
        end
      end

      // TLP into the retry buffer: CRC over sequence number and TLP, one byte per cycle
      if (t_ready) begin
        building <= 1'b1;
        len16    <= t_len16;
        t_hold   <= t_data;
        crc_in   <= {t_data, tx_seq[7:0], 4'b0, tx_seq[11:8]};
        crc_n    <= 0;
        crc      <= 32'hFFFFFFFF;
        rb_seq   <= tx_seq;
      end else if (building) begin
        crc    <= crc32_byte(crc, crc_in[7:0]);
        crc_in <= crc_in >> 8;
        crc_n  <= crc_n + 1;
      end
      if (crc_last) begin
        building <= 1'b0;
        rb_valid <= 1'b1;
        rb_send  <= 1'b1;
        rb_d <= 256'b0;
        rb_k <= 32'b1;
        rb_d[23:0] <= {rb_seq[7:0], 4'b0, rb_seq[11:8], STP};
        rb_d[24 +: 128] <= len16 ? t_hold : {32'b0, t_hold[95:0]};
        if (len16) begin
          rb_d[19 * 8 +: 40] <= {END, lcrc};
          rb_k[23] <= 1'b1;
        end else begin
          rb_d[15 * 8 +: 40] <= {END, lcrc};
          rb_k[19] <= 1'b1;
        end
      end

      // receive, L0 only
      if (ltssm == S_L0) begin
        if (rk[0] && rs[0] == SDP && rk[7] && rs[7] == END &&
            {rs[6], rs[5]} == crc16({rs[4], rs[3], rs[2], rs[1]})) begin
          case (rs[1][7:4])
            4'h0: if (rb_valid && {rs[3][3:0], rs[4]} == rb_seq) begin
                    rb_valid <= 1'b0; rb_send <= 1'b0; tx_seq <= tx_seq + 1; t_done <= 1'b1;
                  end
            4'h1: if (rb_valid) begin rb_send <= 1'b1; replays <= replays + 1; end
            4'h4, 4'h5, 4'h6: begin
                    fc1_seen[rs[1][5:4]] <= 1'b1;
                    if (fc == FC1 && &(fc1_seen | (3'b1 << rs[1][5:4]))) fc <= FC2;
                  end
            4'hC, 4'hD, 4'hE: begin
                    if (fc == FC1) fc <= FC2;
                    fc2_rx <= 1'b1;
                  end
            default: ;
          endcase
        end
        if (fc == FC2 && fc2_rx && fc2_sent == 2'd3) fc <= FCA;

        case (rp_st)
          2'd0: if (rk[0] && rs[0] == STP) begin
            for (i = 0; i < 16; i = i + 1) begin rp_d[i * 8 +: 8] <= rs[i]; rp_k[i] <= rk[i]; end
            rp_st <= 2'd1;
          end
          2'd1: begin
            for (i = 0; i < 16; i = i + 1) begin rp_d[(16 + i) * 8 +: 8] <= rs[i]; rp_k[16 + i] <= rk[i]; end
            rp_st  <= 2'd2;
            rp_n   <= 5'd1;
            rp_crc <= 32'hFFFFFFFF;
            rp_l16 <= rk[7] && rs[7] == END;     // END at symbol 23
          end
          default: begin
            rp_crc <= crc32_byte(rp_crc, rp_d[rp_n * 8 +: 8]);
            rp_n   <= rp_n + 1;
            if (rp_n == (rp_l16 ? 5'd19 : 5'd15)) begin
              rp_st <= 2'd0;
              if (rp_good) begin
                if ({rp_d[11:8], rp_d[23:16]} == rx_seq) begin
                  r_valid <= 1'b1;
                  r_data  <= rp_d[24 +: 128];
                  rx_seq  <= rx_seq + 1;
                  ack_seq <= rx_seq;
                  if (fc == FC2) fc2_rx <= 1'b1;
                end else ack_seq <= rx_seq - 1;
                ack_pend <= 1'b1;
              end else nak_pend <= 1'b1;
            end
          end
        endcase
      end else begin
        rp_st <= 0; fc <= FC1; fc1_seen <= 0; fc2_sent <= 0; fc2_rx <= 1'b0;
      end
    end
  end
endmodule
