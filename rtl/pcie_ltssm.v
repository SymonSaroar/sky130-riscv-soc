// PCIe logical physical layer for an x1 Gen1 Downstream Port, four symbols per pclk, symbol 0 in bits 7:0.
// Receive: symbols flagged on RX_STATUS errors, ordered sets parsed from a stream realigned on every COM, logical idle
// counted. Transmit: training sets, SKP ordered sets every 1280 symbol times at ordered set or packet boundaries,
// EIOS before electrical idle, the compliance pattern, and data link layer words in L0.
module pcie_ltssm #(parameter TSCALE = 1) (
  input             clk,
  input             rst,
  input      [31:0] r_data,
  input       [3:0] r_k,
  input       [5:0] r_st,
  input       [1:0] r_val,
  input       [1:0] r_phys,
  input             r_ei,
  output reg [31:0] t_data,
  output reg  [3:0] t_k,
  output reg  [1:0] t_comp,
  output reg        t_ei,
  output reg        t_det,
  output reg        t_pol,
  output reg  [1:0] t_pd,
  // received symbols for the data link layer
  output reg [31:0] d_data,
  output reg  [3:0] d_k,
  output reg  [3:0] d_err,
  output            d_en,
  // transmit words from the data link layer: l_busy while a packet is in progress, l_ok when a word is taken
  input      [31:0] l_data,
  input       [3:0] l_k,
  input             l_busy,
  output            l_ok,
  input             retrain,
  input             dir_retrain,
  input             dir_hot_reset,
  output reg        link_up,
  output            l0,
  output reg  [4:0] state,
  output reg  [7:0] recoveries
);
  localparam [7:0] COM = 8'hBC, SKP = 8'h1C, PAD = 8'hF7, IDL = 8'h7C, FTS = 8'h3C,
                   TS1 = 8'h4A, TS2 = 8'h45, TS1I = 8'hB5, TS2I = 8'hBA, D21_5 = 8'hB5, D10_2 = 8'h4A;
  localparam [4:0] S_DQ = 0, S_DA = 1, S_WAKE = 2, S_PA = 3, S_PCP = 4, S_PC = 5, S_CLS = 6, S_CLA = 7,
                   S_CNW = 8, S_CNA = 9, S_CC = 10, S_CI = 11, S_L0 = 12, S_RL = 13, S_RC = 14, S_RI = 15,
                   S_HR = 16;
  localparam [1:0] P0 = 2'b00, P1 = 2'b10;
  localparam integer MS = 62500 / TSCALE;
  localparam [31:0] W1 = MS, W2 = 2 * MS, W12 = 12 * MS, W24 = 24 * MS, W48 = 48 * MS;
  localparam [21:0] T1 = W1[21:0], T2 = W2[21:0], T12 = W12[21:0], T24 = W24[21:0], T48 = W48[21:0];
  localparam [2:0] X_TS = 0, X_EI = 1, X_EIOS = 2, X_SKP = 3, X_IDLE = 4, X_DATA = 5, X_COMP = 6;

  assign l0   = state == S_L0;
  assign d_en = link_up;

  // ---------------- receive ----------------
  reg [31:0] p_data;
  reg  [3:0] p_k, p_err;
  reg  [1:0] off;
  reg        ostart, ts_on, ts_bad, id_bad;
  reg  [1:0] osw;
  reg  [7:0] f_link, f_lane, f_rate, f_ctrl, f_id;
  reg        f_lpad, f_wpad;
  // events, one clock
  reg        ts_ev, inv_ev, skp_ev, eios_ev;
  reg  [7:0] e_link, e_lane, e_rate, e_ctrl, e_id;
  reg        e_lpad, e_wpad;
  reg  [3:0] idle_run;

  // stage 1: symbols and their error flags
  reg  [3:0] err_n;
  integer    i;
  always @* for (i = 0; i < 4; i = i + 1)
    err_n[i] = !r_val[i / 2] || r_st[(i / 2) * 3 + 2];

  // the aligned word: four symbols of {previous, current} starting at off
  wire [63:0] wd = {d_data, p_data};
  wire  [7:0] wk = {d_k, p_k};
  wire  [7:0] we = {d_err, p_err};
  reg   [7:0] a [0:3];
  reg   [3:0] ak, ae;
  always @* for (i = 0; i < 4; i = i + 1) begin
    a[i]  = wd[({30'd0, off} + i) * 8 +: 8];
    ak[i] = wk[{30'd0, off} + i];
    ae[i] = we[{30'd0, off} + i];
  end

  // last COM in the current word
  reg [1:0] com_pos;
  reg       com_any;
  always @* begin
    com_any = 1'b0; com_pos = 2'd0;
    for (i = 0; i < 4; i = i + 1)
      if (d_k[i] && d_data[i * 8 +: 8] == COM && !d_err[i]) begin com_any = 1'b1; com_pos = i[1:0]; end
  end

  // logical idle run over the current word; COM and SKP do not interrupt it
  reg [3:0] run;
  always @* begin
    run = idle_run;
    for (i = 0; i < 4; i = i + 1)
      if (!d_k[i] && d_data[i * 8 +: 8] == 8'h00 && !d_err[i]) run = run == 4'hF ? run : run + 4'd1;
      else if (!(d_k[i] && !d_err[i] && (d_data[i * 8 +: 8] == COM || d_data[i * 8 +: 8] == SKP))) run = 4'd0;
  end

  wire ids = !ak[0] && !ak[1] && !ak[2] && !ak[3] && !ae[0] && !ae[1] && !ae[2] && !ae[3] &&
             a[0] == f_id && a[1] == f_id && a[2] == f_id && a[3] == f_id;
  wire [1:0] idls = {1'b0, ak[1] && a[1] == IDL} + {1'b0, ak[2] && a[2] == IDL} + {1'b0, ak[3] && a[3] == IDL};

  always @(posedge clk) begin
    p_data <= d_data; p_k <= d_k; p_err <= d_err;
    d_data <= r_data; d_k <= r_k; d_err <= err_n;
    if (com_any) off <= com_pos;
    ostart <= com_any;
    idle_run <= run;
    ts_ev <= 1'b0; inv_ev <= 1'b0; skp_ev <= 1'b0; eios_ev <= 1'b0;
    if (rst) begin
      ts_on <= 1'b0; ostart <= 1'b0; off <= 2'd0; idle_run <= 4'd0;
    end else if (ostart) begin
      ts_on <= 1'b0;
      osw   <= 2'd1;
      if (ak[1] && a[1] == SKP) skp_ev <= 1'b1;
      else if (idls >= 2'd2) eios_ev <= 1'b1;
      else if (!(ak[1] && a[1] == FTS)) begin
        ts_on  <= 1'b1;
        f_lpad <= ak[1]; f_link <= a[1];
        f_wpad <= ak[2]; f_lane <= a[2];
        ts_bad <= ae[1] || ae[2] || ae[3] || ak[3] || (ak[1] && a[1] != PAD) || (ak[2] && a[2] != PAD);
        id_bad <= 1'b0;
      end
    end else if (ts_on) begin
      osw <= osw + 2'd1;
      if (osw == 2'd1) begin
        f_rate <= a[0]; f_ctrl <= a[1]; f_id <= a[2];
        if (ak[0] || ak[1] || ae[0] || ae[1]) ts_bad <= 1'b1;
        if (ak[2] || ak[3] || ae[2] || ae[3] || a[3] != a[2]) id_bad <= 1'b1;
      end else begin
        if (!ids) id_bad <= 1'b1;
        if (osw == 2'd3) begin
          ts_on <= 1'b0;
          if (ids && !id_bad) begin
            if ((f_id == TS1 || f_id == TS2) && !ts_bad) begin
              ts_ev <= 1'b1;
              e_link <= f_link; e_lane <= f_lane; e_lpad <= f_lpad; e_wpad <= f_wpad;
              e_rate <= f_rate; e_ctrl <= f_ctrl; e_id <= f_id;
            end
            if (f_id == TS1I || f_id == TS2I) inv_ev <= 1'b1;
          end
        end
      end
    end
  end

  // ---------------- state machine ----------------
  reg  [21:0] tmr;
  reg         to1, to2, to12, to24, to48;   // time in state reached, a clock late
  reg  [10:0] ts_cnt;       // training sets sent in this state
  reg   [4:0] ts_after;     // sent since one of the expected type was received
  reg   [3:0] cons;         // consecutive matching training sets received
  reg         got8;         // eight consecutive were received in this state
  reg   [7:0] last_id;
  reg         seen, seen_any, ei_exit, phy_rdy, pd_busy, rlock_done, hr_req, rt_req, rt_q, hr_q;
  reg   [3:0] cons_lane2, cons_cfg, cons_pp;
  reg   [2:0] idle_sent;    // idle words sent since one idle symbol was received
  reg  [12:0] skp_rx_t;     // clocks since a SKP ordered set was received
  reg   [8:0] skp_cnt;      // words sent since the last SKP ordered set
  reg   [1:0] tsw;          // word of the training set in progress
  reg         tx_on;        // the transmitter left electrical idle and owes an EIOS before returning
  reg   [2:0] x_last;
  reg   [7:0] c_id, c_ctrl;
  reg         c_link, c_lane;

  // what the state receives as a match, and what it sends
  wire        e_pp   = e_lpad && e_link == PAD && e_wpad && e_lane == PAD;
  wire        e_00   = !e_lpad && e_link == 8'd0 && !e_wpad && e_lane == 8'd0;
  reg         match;
  always @* case (state)
    S_PA:              match = e_pp && (e_id == TS2 || !e_ctrl[4] || e_ctrl[2]);
    S_PC:              match = e_pp && e_id == TS2;
    S_CLS:             match = e_id == TS1 && !e_lpad && e_link == 8'd0 && e_wpad && e_lane == PAD;
    S_CNW, S_CNA:      match = e_id == TS1 && e_00;
    S_CC, S_RC:        match = e_id == TS2 && e_00 && !e_rate[7];
    S_RL:              match = e_00 && !e_rate[7];
    S_HR:              match = e_id == TS1 && e_ctrl[0];
    default:           match = 1'b0;
  endcase
  wire [3:0] cons_n = ts_ev ? (match ? (e_id == last_id && cons != 4'hF ? cons + 4'd1 : (e_id == last_id ? cons : 4'd1))
                                     : 4'd0) : cons;
  wire       pad_ts1  = ts_ev && e_id == TS1 && e_pp;
  wire       lane_pad = ts_ev && e_id == TS1 && e_wpad && e_lane == PAD;

  wire [1:0] det_st = r_phys[0] ? (r_st[2:0] == 3'b011 ? 2'b11 : 2'b10) :
                     r_phys[1] ? (r_st[5:3] == 3'b011 ? 2'b11 : 2'b10) : 2'b00;

  reg  [4:0] nst;
  reg        go;
  always @* begin
    nst = state; go = 1'b0;
    case (state)
      S_DQ:   if (phy_rdy && !pd_busy && t_ei && t_pd == P1 && (!r_ei || to12)) begin nst = S_DA; go = 1'b1; end
      S_DA:   if (det_st == 2'b11) begin nst = S_WAKE; go = 1'b1; end
              else if (det_st == 2'b10 || to1) begin nst = S_DQ; go = 1'b1; end
      S_WAKE: if (!pd_busy && t_pd == P0) begin nst = S_PA; go = 1'b1; end
              else if (to1) begin nst = S_DQ; go = 1'b1; end
      S_PA:   if (got8 && ts_cnt >= 11'd1024) begin nst = S_PC; go = 1'b1; end
              else if (to24) begin
                nst = got8 ? S_PC : !ei_exit ? S_PCP : S_DQ; go = 1'b1;
              end
      S_PCP:  if (!r_ei) begin nst = S_PA; go = 1'b1; end
      S_PC:   if (got8 && ts_after >= 5'd16) begin nst = S_CLS; go = 1'b1; end
              else if (to48) begin nst = S_DQ; go = 1'b1; end
      S_CLS:  if (cons >= 4'd2) begin nst = S_CLA; go = 1'b1; end
              else if (to24) begin nst = S_DQ; go = 1'b1; end
      S_CLA:  if (ts_cnt >= 11'd1) begin nst = S_CNW; go = 1'b1; end
              else if (to2) begin nst = S_DQ; go = 1'b1; end
      S_CNW:  if (cons >= 4'd2) begin nst = S_CNA; go = 1'b1; end
              else if (to2 || cons_pp >= 4'd2) begin nst = S_DQ; go = 1'b1; end
      S_CNA:  if (cons >= 4'd2) begin nst = S_CC; go = 1'b1; end
              else if (to2 || cons_pp >= 4'd2) begin nst = S_DQ; go = 1'b1; end
      S_CC:   if (got8 && ts_after >= 5'd16) begin nst = S_CI; go = 1'b1; end
              else if (to2) begin nst = S_DQ; go = 1'b1; end
      S_CI, S_RI:
              if (idle_run >= 4'd8 && idle_sent >= 3'd4) begin nst = S_L0; go = 1'b1; end
              else if (state == S_RI && hr_req) begin nst = S_HR; go = 1'b1; end
              else if (state == S_RI && cons_lane2 >= 4'd2) begin nst = S_CLS; go = 1'b1; end
              else if (to2) begin nst = rlock_done ? S_DQ : S_RL; go = 1'b1; end
      S_L0:   if (ts_ev || eios_ev || retrain || rt_req || hr_req || skp_rx_t >= 13'd8000) begin nst = S_RL; go = 1'b1; end
      S_RL:   if (got8) begin nst = S_RC; go = 1'b1; end
              else if (to24) begin nst = seen ? S_CLS : S_DQ; go = 1'b1; end
      S_RC:   if (got8 && ts_after >= 5'd16) begin nst = S_RI; go = 1'b1; end
              else if (cons_cfg >= 4'd8 && ts_after >= 5'd16) begin nst = S_CLS; go = 1'b1; end
              else if (to48) begin nst = S_DQ; go = 1'b1; end
      S_HR:   if ((cons >= 4'd2 && tmr >= 22'd64) || to2) begin nst = S_DQ; go = 1'b1; end
      default: begin nst = S_DQ; go = 1'b1; end
    endcase
    if (rst) begin nst = S_DQ; go = 1'b1; end
  end

  // RI: TS1 with Lane PAD; RC: TS1 with other Link or Lane numbers; Configuration: TS1 with Link and Lane PAD
  always @(posedge clk)
    if (rst || go) begin cons_lane2 <= 4'd0; cons_cfg <= 4'd0; cons_pp <= 4'd0; end
    else if (ts_ev) begin
      cons_lane2 <= lane_pad ? (cons_lane2 == 4'hF ? cons_lane2 : cons_lane2 + 4'd1) : 4'd0;
      cons_cfg   <= e_id == TS1 && !e_00 ? (cons_cfg == 4'hF ? cons_cfg : cons_cfg + 4'd1) : 4'd0;
      cons_pp    <= pad_ts1 ? (cons_pp == 4'hF ? cons_pp : cons_pp + 4'd1) : 4'd0;
    end

  // the expected type of training set, for "sent after receiving one"
  wire want_ts2 = state == S_PC || state == S_CC || state == S_RC;

  always @(posedge clk)
    if (go) {to1, to2, to12, to24, to48} <= 5'b0;
    else {to1, to2, to12, to24, to48} <= {tmr >= T1, tmr >= T2, tmr >= T12, tmr >= T24, tmr >= T48};

  always @(posedge clk) begin
    // directed retrain and hot reset act on the rising edge of the register bits
    rt_q <= dir_retrain; hr_q <= dir_hot_reset;
    if (dir_retrain && !rt_q) rt_req <= 1'b1;
    if (dir_hot_reset && !hr_q) hr_req <= 1'b1;
    if (r_phys == 2'b00) phy_rdy <= 1'b1;
    if (pd_busy && |r_phys) pd_busy <= 1'b0;
    skp_rx_t <= skp_ev || state != S_L0 ? 13'd0 : skp_rx_t == 13'h1FFF ? skp_rx_t : skp_rx_t + 13'd1;
    if (ts_ev) last_id <= e_id;
    cons <= cons_n;
    if (cons_n >= 4'd8) got8 <= 1'b1;
    tmr <= tmr + 22'd1;
    if (!r_ei) ei_exit <= 1'b1;
    if (ts_ev && match) seen <= 1'b1;
    if (ts_ev && (want_ts2 ? e_id == TS2 : e_id == TS1) && !seen_any) seen_any <= 1'b1;
    if ((state == S_PA || state == S_PC) && inv_ev) t_pol <= 1'b1;
    if (go) begin
      state <= nst; tmr <= 22'd0; cons <= 4'd0; got8 <= 1'b0; seen <= 1'b0; seen_any <= 1'b0; ei_exit <= 1'b0;
      case (nst)
        S_DQ:   begin link_up <= 1'b0; t_pol <= 1'b0; t_det <= 1'b0; end
        S_DA:   t_det <= 1'b1;
        S_WAKE: begin t_det <= 1'b0; t_pd <= P0; pd_busy <= 1'b1; end
        S_CI:   link_up <= 1'b1;
        S_L0:   rlock_done <= 1'b0;
        S_RL:   begin
          if (state == S_L0) begin recoveries <= recoveries == 8'hFF ? recoveries : recoveries + 8'd1; rt_req <= 1'b0; end
          if (state == S_CI || state == S_RI) rlock_done <= 1'b1;
        end
        S_HR:   begin hr_req <= 1'b0; link_up <= 1'b0; end
        default: ;
      endcase
    end
    if (state == S_DA && det_st != 2'b00) t_det <= 1'b0;
    // into P1 once the transmitter is idle in Detect
    if (state == S_DQ && t_ei && t_pd != P1 && !pd_busy) begin t_pd <= P1; pd_busy <= 1'b1; end
    if (rst) begin
      state <= S_DQ; link_up <= 1'b0; t_pol <= 1'b0; t_det <= 1'b0; t_pd <= P1; pd_busy <= 1'b0; phy_rdy <= 1'b0;
      rlock_done <= 1'b0; hr_req <= 1'b0; rt_req <= 1'b0; recoveries <= 8'd0; cons <= 4'd0; got8 <= 1'b0; last_id <= 8'd0;
    end
  end
  // ---------------- transmit ----------------
  reg [2:0] x;
  always @* begin
    if (tsw != 2'd0) x = X_TS;
    else if (x_last == X_DATA && l_busy) x = X_DATA;
    else case (state)
      S_DQ, S_DA, S_WAKE: x = tx_on ? X_EIOS : X_EI;
      default:
        if (skp_cnt >= 9'd320 && state != S_PCP) x = X_SKP;
        else case (state)
          S_PCP:       x = X_COMP;
          S_CI, S_RI:  x = X_IDLE;
          S_L0:        x = X_DATA;
          default:     x = X_TS;
        endcase
    endcase
  end
  assign l_ok = x == X_DATA;

  // training set fields for the state
  wire       s_ts2  = state == S_PC || state == S_CC || state == S_RC;
  wire       s_link = !(state == S_PA || state == S_PC);
  wire       s_lane = !(state == S_PA || state == S_PC || state == S_CLS);
  wire [7:0] s_ctrl = state == S_HR ? 8'h01 : 8'h00;

  always @(posedge clk) begin
    x_last <= x;
    t_comp <= 2'b00;
    if (x != X_EI) skp_cnt <= x == X_SKP ? 9'd0 : skp_cnt + 9'd1;
    else skp_cnt <= 9'd0;
    case (x)
      X_EI:   begin t_ei <= 1'b1; t_data <= 32'h0; t_k <= 4'h0; end
      X_EIOS: begin t_ei <= 1'b0; tx_on <= 1'b0; t_data <= {IDL, IDL, IDL, COM}; t_k <= 4'hF; end
      X_SKP:  begin t_ei <= 1'b0; tx_on <= 1'b1; t_data <= {SKP, SKP, SKP, COM}; t_k <= 4'hF; end
      X_IDLE: begin
        t_ei <= 1'b0; tx_on <= 1'b1; t_data <= 32'h0; t_k <= 4'h0;
        if ((idle_run != 4'd0 || run != 4'd0) && idle_sent != 3'h7) idle_sent <= idle_sent + 3'd1;
      end
      X_DATA: begin t_ei <= 1'b0; tx_on <= 1'b1; t_data <= l_data; t_k <= l_k; end
      X_COMP: begin t_ei <= 1'b0; tx_on <= 1'b1; t_data <= {D10_2, COM, D21_5, COM}; t_k <= 4'b0101; t_comp <= 2'b01; end
      default: begin
        t_ei <= 1'b0; tx_on <= 1'b1;
        tsw <= tsw + 2'd1;
        case (tsw)
          2'd0: begin
            c_id <= s_ts2 ? TS2 : TS1; c_ctrl <= s_ctrl; c_link <= s_link; c_lane <= s_lane;
            t_data <= {8'd255, s_lane ? 8'd0 : PAD, s_link ? 8'd0 : PAD, COM};
            t_k <= {1'b0, !s_lane, !s_link, 1'b1};
            ts_cnt <= ts_cnt == 11'h7FF ? ts_cnt : ts_cnt + 11'd1;
            if (seen_any && ts_after != 5'h1F) ts_after <= ts_after + 5'd1;
          end
          2'd1: begin t_data <= {c_id, c_id, c_ctrl, 8'h02}; t_k <= 4'h0; end
          default: begin t_data <= {4{c_id}}; t_k <= 4'h0; end
        endcase
      end
    endcase
    if (go) begin ts_cnt <= 11'd0; ts_after <= 5'd0; idle_sent <= 3'd0; end
    if (rst) begin
      t_ei <= 1'b1; t_data <= 32'h0; t_k <= 4'h0; tsw <= 2'd0; tx_on <= 1'b0; skp_cnt <= 9'd0; x_last <= X_EI;
    end
  end
endmodule
