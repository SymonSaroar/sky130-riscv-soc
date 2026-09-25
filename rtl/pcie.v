// PCIe x1 root port for a TI XIO1100 PHY. AXI4-Lite slave and APB registers on clk; transaction layer, data link
// layer and LTSSM on pclk; TI-PIPE registers on pipe_rx_clk.
// AXI: 0x4000_0000 to 0x4FFF_FFFF become MRd32 and MWr32 of one DW at the same address; 0x5000_0000 to
// 0x5FFF_FFFF are configuration space in ECAM layout, CfgRd0 and CfgWr0 to bus 1, device 0. One request in flight.
// A request that fails returns FFFF_FFFFh and sets a bit in ERROR.
// APB: 0x0 STATUS {recoveries, replays, 0, LTSSM state, LinkUp, DL_Up}; 0x4 CONTROL bit 0 PHY reset (reset 1),
// bit 1 Hot Reset, bit 2 retrain; 0x8 ERROR, write 1 to clear: bit 0 completion timeout, 1 UR, 2 CA, 3 RRS,
// 4 bad TLP, 5 bad DLLP, 6 receiver error, 7 malformed TLP, 8 inbound TLP answered with UR or dropped.
module pcie #(parameter TSCALE = 1) (
  input             clk,
  input             rst,
  input      [31:0] awaddr,
  input             awvalid,
  output            awready,
  input      [31:0] wdata,
  input       [3:0] wstrb,
  input             wvalid,
  output            wready,
  output            bvalid,
  input             bready,
  input      [31:0] araddr,
  input             arvalid,
  output            arready,
  output     [31:0] rdata,
  output            rvalid,
  input             rready,
  input             psel,
  input             penable,
  input             pwrite,
  input       [3:2] paddr,
  input      [31:0] pwdata,
  output reg [31:0] prdata,
  // TI-PIPE
  input             pipe_rx_clk,
  input      [15:0] pipe_rx_data,
  input       [1:0] pipe_rx_datak,
  input       [2:0] pipe_rx_status,
  input             pipe_rx_valid,
  input             pipe_phy_status,
  input             pipe_rx_elecidle,
  output            pipe_tx_clk,
  output     [15:0] pipe_tx_data,
  output      [1:0] pipe_tx_datak,
  output            pipe_tx_elecidle,
  output            pipe_tx_compliance,
  output            pipe_tx_det_loopback,
  output            pipe_rx_polarity,
  output      [1:0] pipe_powerdown,
  output            pipe_reset_n
);
  localparam [2:0] E_OK = 3'd0, E_UR = 3'd1, E_CA = 3'd2, E_RRS = 3'd3, E_TO = 3'd4;

  // ---------------- clk side ----------------
  reg  [2:0] ctrl;
  reg  [8:0] err;
  reg        arst, crst, busy, pend_wr, lresp;
  wire       wr = awvalid && wvalid;
  wire       cfull, rempty;
  wire [34:0] rsp;
  wire       resp_ready = lresp || !rempty;
  assign awready = !busy && !cfull && wr;
  assign wready  = awready;
  assign arready = !busy && !cfull && arvalid && !wr;
  assign rvalid  = busy && resp_ready && !pend_wr;
  assign bvalid  = busy && resp_ready && pend_wr;
  assign rdata   = lresp ? 32'hFFFF_FFFF : rsp[31:0];
  wire   resp_ok = rvalid && rready || bvalid && bready;
  assign pipe_reset_n = !ctrl[0];

  // pclk status and error events, synchronized
  wire [23:0] st_p;
  reg  [23:0] st1, st2;
  wire  [4:0] ev_p;           // toggles: bad TLP, bad DLLP, receiver error, malformed, inbound
  reg   [4:0] ev1, ev2, ev3;

  always @* case (paddr)
    2'd0:    prdata = {8'b0, st2};
    2'd1:    prdata = {29'b0, ctrl};
    default: prdata = {23'b0, err};
  endcase

  wire [2:0] rcode = lresp ? E_UR : rsp[34:32];
  wire [8:0] err_set = {ev3 ^ ev2, resp_ok && rcode == E_RRS, resp_ok && rcode == E_CA, resp_ok && rcode == E_UR,
                        resp_ok && rcode == E_TO};
  always @(posedge clk) begin
    {st2, st1} <= {st1, st_p};
    {ev3, ev2, ev1} <= {ev2, ev1, ev_p};
    arst <= rst || ctrl[0];
    crst <= rst || ctrl[0];
    if (rst) begin
      busy <= 1'b0; pend_wr <= 1'b0; lresp <= 1'b0; ctrl <= 3'b001; err <= 9'b0;
    end else begin
      if (awready || arready) begin busy <= 1'b1; pend_wr <= wr; lresp <= ctrl[0]; end
      else if (resp_ok) begin busy <= 1'b0; lresp <= 1'b0; end
      if (psel && penable && pwrite && paddr == 2'd1) ctrl <= pwdata[2:0];
      err <= err & ~(psel && penable && pwrite && paddr == 2'd2 ? pwdata[8:0] : 9'b0) | err_set;
    end
  end

  // ---------------- clock crossing ----------------
  wire        pclk, prst;
  wire        c_empty;
  reg         c_pop, r_push;
  wire [68:0] c_data;
  reg  [34:0] r_data;
  async_fifo #(.W(69)) u_cmd (
    .wclk(clk), .wrst(crst), .winc((awready || arready) && !ctrl[0]),
    .wdata({wr, wr ? awaddr : araddr, wdata, wstrb}), .wfull(cfull),
    .rclk(pclk), .rrst(prst), .rinc(c_pop), .rdata(c_data), .rempty(c_empty)
  );
  async_fifo #(.W(35)) u_rsp (
    .wclk(pclk), .wrst(prst), .winc(r_push), .wdata(r_data), .wfull(),
    .rclk(clk), .rrst(crst), .rinc(resp_ok && !lresp), .rdata(rsp), .rempty(rempty)
  );

  // ---------------- transaction layer, pclk ----------------
  localparam [1:0] T_IDLE = 2'd0, T_SEND = 2'd1, T_WAIT = 2'd2;
  localparam integer CPL_LIMIT = 625000 / TSCALE;       // 10 ms
  reg   [1:0] st;
  reg         q_wr, q_cfg;
  reg  [31:0] q_addr, q_wd;
  reg   [3:0] q_be;
  reg   [4:0] tag;
  reg  [19:0] tmo;
  wire        dl_up;
  wire        t_ready, r_valid;
  wire [159:0] r_tlp;
  wire  [5:0] r_ndw;
  reg         np_free;
  reg   [3:0] np_free_d;
  reg   [4:0] ev;

  // request header, byte 0 in bits 7:0
  wire [7:0] q_t = q_cfg ? (q_wr ? 8'h44 : 8'h04) : (q_wr ? 8'h40 : 8'h00);
  wire [7:0] q_b11 = {q_addr[7:2], 2'b00};
  wire [95:0] q_hdr = q_cfg
    ? {q_b11, 4'h0, q_addr[11:8], q_addr[19:12], q_addr[27:20], q_wr ? {4'h0, q_be} : 8'h0F, 3'b000, tag, 16'h0000,
       8'h01, 8'h00, 8'h00, q_t}
    : {q_b11, q_addr[15:8], q_addr[23:16], q_addr[31:24], q_wr ? {4'h0, q_be} : 8'h0F, 3'b000, tag, 16'h0000,
       8'h01, 8'h00, 8'h00, q_t};
  wire q_target = q_cfg ? q_addr[27:20] == 8'd1 && q_addr[19:15] == 5'd0 : q_addr[29:28] == 2'b00;

  // received TLP fields
  wire  [7:0] rb0 = r_tlp[7:0], rb1 = r_tlp[15:8], rb2 = r_tlp[23:16], rb3 = r_tlp[31:24];
  wire  [9:0] rlen = {rb2[1:0], rb3};
  wire        r4dw = rb0[5];
  wire        rdat = rb0[6];
  wire [10:0] r_dw = rdat ? (rlen == 10'd0 ? 11'd1024 : {1'b0, rlen}) : 11'd0;
  wire [11:0] r_exp = {1'b0, r_dw} + (r4dw ? 12'd4 : 12'd3) + {11'd0, rb2[7]};
  wire        r_mal = r_exp != {6'd0, r_ndw} || r_dw > 11'd32;
  wire        r_cpl = rb0[4:1] == 4'b0101 && !rb0[7] && !rb0[5];       // Cpl, CplD, CplLk, CplDLk
  wire        r_pst = rb0 == 8'h40 || rb0 == 8'h60 || rb0[7:3] == 5'b00110 || rb0[7:3] == 5'b01110;
  wire        r_np  = rb0 == 8'h00 || rb0 == 8'h20 || rb0 == 8'h01 || rb0 == 8'h21 || rb0 == 8'h02 ||
                      rb0 == 8'h42 || rb0 == 8'h04 || rb0 == 8'h05 || rb0 == 8'h44 || rb0 == 8'h45 ||
                      rb0 == 8'h4C || rb0 == 8'h4D || rb0 == 8'h4E || rb0 == 8'h6C || rb0 == 8'h6D || rb0 == 8'h6E;
  wire [31:0] rdw1 = r_tlp[63:32], rdw2 = r_tlp[95:64];
  wire        r_mine = r_cpl && rdw2[15:0] == 16'h0000 && rdw2[23:16] == {3'b000, tag} && st == T_WAIT;
  wire  [2:0] r_cst = rdw1[23:21];

  // UR completions for Non-Posted requests from the device. Entry: completion bytes 1 and 2, requester ID bytes,
  // tag, byte count, lower address, and the data credits the request used.
  reg  [62:0] urq [0:3];
  reg   [1:0] ur_h, ur_t;
  reg   [2:0] ur_n;
  wire  [3:0] fbe = rdw1[27:24], lbe = rdw1[31:28];
  wire  [1:0] lead  = fbe[0] ? 2'd0 : fbe[1] ? 2'd1 : fbe[2] ? 2'd2 : 2'd3;
  wire  [1:0] trail = lbe[3] ? 2'd0 : lbe[2] ? 2'd1 : lbe[1] ? 2'd2 : 2'd3;
  wire [11:0] bc_mrd = rlen == 10'd1 ? (fbe[0] && fbe[3] ? 12'd4 : (fbe[0] && fbe[2]) || (fbe[1] && fbe[3]) ? 12'd3 :
                                        fbe == 4'b0011 || fbe == 4'b0110 || fbe == 4'b1100 ? 12'd2 : 12'd1)
                                     : {r_dw[9:0], 2'b00} - {10'd0, lead} - {10'd0, trail};
  wire        r_mem = rb0[4:1] == 4'b0000;                              // MRd, MRdLk
  wire  [7:0] r_alo = r4dw ? r_tlp[127:120] : r_tlp[95:88];
  wire [11:0] r_bc  = r_mem ? bc_mrd : rb0 == 8'h02 || rb0 == 8'h42 || rb0[4:1] == 4'b0010 ? 12'd4 : {r_dw[9:0], 2'b00};
  wire  [6:0] r_la  = r_mem ? {r_alo[6:2], lead} : 7'd0;
  wire  [3:0] r_npd = rdat ? r_dw[5:2] + {3'b000, |r_dw[1:0]} : 4'd0;
  wire [62:0] ur_e  = {rb1[7:2], 2'b00, 2'b00, rb2[5:4], 4'h0, rdw1[7:0], rdw1[15:8], rdw1[23:16], r_bc, r_la, r_npd};
  wire [62:0] ue    = urq[ur_h];
  // Cpl, status UR, completer 0000h
  wire [95:0] ur_hdr = {1'b0, ue[10:4], ue[30:23], ue[38:31], ue[46:39], ue[18:11], 3'b001, 1'b0, ue[22:19],
                        16'h0000, 8'h00, ue[54:47], ue[62:55], 8'h0A};

  // the posted request in flight goes first; completions pass Non-Posted requests
  wire        ur_go  = ur_n != 3'd0 && !(st == T_SEND && q_wr && !q_cfg);
  wire        t_valid = ur_go || (st == T_SEND && q_target);
  wire        t_take  = t_valid && t_ready;

  always @(posedge pclk) begin
    c_pop <= 1'b0; r_push <= 1'b0; np_free <= 1'b0;
    if (st == T_WAIT) tmo <= tmo + 20'd1;
    case (st)
      T_IDLE: if (!c_empty && !c_pop) begin
        {q_wr, q_addr, q_wd, q_be} <= c_data[68:0];
        q_cfg <= c_data[67:64] == 4'h5;
        c_pop <= 1'b1; st <= T_SEND; tag <= tag + 5'd1;
      end
      T_SEND: if (!q_target) begin r_data <= {E_UR, 32'hFFFF_FFFF}; r_push <= 1'b1; st <= T_IDLE; end
              else if (t_take && !ur_go) begin
                tmo <= 20'd0;
                if (q_wr && !q_cfg) begin r_data <= {E_OK, 32'h0}; r_push <= 1'b1; st <= T_IDLE; end
                else st <= T_WAIT;
              end else if (!dl_up) begin r_data <= {E_UR, 32'hFFFF_FFFF}; r_push <= 1'b1; st <= T_IDLE; end
      default: if (r_valid && r_mine) begin
                 r_push <= 1'b1; st <= T_IDLE;
                 if (r_cst == 3'b000 && (q_wr ? !rdat : rdat && rlen == 10'd1)) r_data <= {E_OK, q_wr ? 32'h0 : r_tlp[127:96]};
                 else if (r_cst == 3'b000) r_data <= {E_UR, 32'hFFFF_FFFF};
                 else r_data <= {r_cst == 3'b010 ? E_RRS : r_cst == 3'b100 ? E_CA : E_UR, 32'hFFFF_FFFF};
               end else if (!dl_up) begin r_data <= {E_UR, 32'hFFFF_FFFF}; r_push <= 1'b1; st <= T_IDLE; end
               else if (tmo >= CPL_LIMIT[19:0]) begin r_data <= {E_TO, 32'hFFFF_FFFF}; r_push <= 1'b1; st <= T_IDLE; end
    endcase

    // TLPs from the device that are not our completion
    if (r_valid && !r_mine) begin
      if (r_np) begin
        if (r_mal) ev[3] <= !ev[3];
        else begin urq[ur_t] <= ur_e; ur_t <= ur_t + 2'd1; ur_n <= ur_n + 3'd1; end
        ev[4] <= !ev[4];
        if (r_mal) begin np_free <= 1'b1; np_free_d <= r_npd; end
      end else if (r_pst || r_cpl) begin
        if (r_mal) ev[3] <= !ev[3];
        ev[4] <= !ev[4];
      end else ev[3] <= !ev[3];
    end
    if (t_take && ur_go) begin
      ur_h <= ur_h + 2'd1; np_free <= 1'b1; np_free_d <= ue[3:0];
      if (!(r_valid && !r_mine && r_np && !r_mal)) ur_n <= ur_n - 3'd1; else ur_n <= ur_n;
    end
    if (!dl_up) begin ur_h <= 2'd0; ur_t <= 2'd0; ur_n <= 3'd0; end
    if (prst) begin st <= T_IDLE; tag <= 5'd0; ur_h <= 2'd0; ur_t <= 2'd0; ur_n <= 3'd0; ev <= 5'd0; end
  end

  // ---------------- link ----------------
  wire [31:0] r_d, t_d, d_data, l_data;
  wire  [3:0] r_k, t_k, d_k, d_err, l_k;
  wire  [5:0] r_st;
  wire  [1:0] r_val, r_phys, t_comp, t_pd;
  wire        r_ei, t_ei, t_det, t_pol, d_en, l_busy, l_ok, retrain, link_up, l0;
  wire  [4:0] ltssm;
  wire  [7:0] recoveries, replays;
  wire        e_tlp, e_dllp, e_rx;
  reg   [1:0] hr_s, rt_s;
  always @(posedge pclk) begin hr_s <= {hr_s[0], ctrl[1]}; rt_s <= {rt_s[0], ctrl[2]}; end
  // status and event toggles for clk, held at 0 while the PHY or pclk is in reset
  reg   [2:0] e_t;
  reg  [23:0] st_q;
  reg   [4:0] ev_q;
  always @(posedge pclk)
    if (prst) e_t <= 3'b0;
    else e_t <= e_t ^ {e_rx, e_dllp, e_tlp};
  always @(posedge pclk or posedge arst)
    if (arst) begin st_q <= 24'b0; ev_q <= 5'b0; end
    else if (prst) begin st_q <= 24'b0; ev_q <= 5'b0; end
    else begin
      st_q <= {recoveries, replays, 1'b0, ltssm, link_up, dl_up};
      ev_q <= {ev[4], ev[3], e_t[2], e_t[1], e_t[0]};
    end
  assign ev_p = ev_q;
  assign st_p = st_q;

  pcie_pipe u_pipe (
    .arst(arst), .rx_clk(pipe_rx_clk),
    .rx_data(pipe_rx_data), .rx_datak(pipe_rx_datak), .rx_status(pipe_rx_status), .rx_valid(pipe_rx_valid),
    .phy_status(pipe_phy_status), .rx_elecidle(pipe_rx_elecidle),
    .tx_clk(pipe_tx_clk), .tx_data(pipe_tx_data), .tx_datak(pipe_tx_datak), .tx_elecidle(pipe_tx_elecidle),
    .tx_compliance(pipe_tx_compliance), .tx_det_lb(pipe_tx_det_loopback), .rx_polarity(pipe_rx_polarity),
    .powerdown(pipe_powerdown),
    .pclk(pclk), .prst(prst),
    .r_data(r_d), .r_k(r_k), .r_st(r_st), .r_val(r_val), .r_phys(r_phys), .r_ei(r_ei),
    .t_data(t_d), .t_k(t_k), .t_comp(t_comp), .t_ei(t_ei), .t_det(t_det), .t_pol(t_pol), .t_pd(t_pd)
  );

  pcie_ltssm #(.TSCALE(TSCALE)) u_ltssm (
    .clk(pclk), .rst(prst),
    .r_data(r_d), .r_k(r_k), .r_st(r_st), .r_val(r_val), .r_phys(r_phys), .r_ei(r_ei),
    .t_data(t_d), .t_k(t_k), .t_comp(t_comp), .t_ei(t_ei), .t_det(t_det), .t_pol(t_pol), .t_pd(t_pd),
    .d_data(d_data), .d_k(d_k), .d_err(d_err), .d_en(d_en),
    .l_data(l_data), .l_k(l_k), .l_busy(l_busy), .l_ok(l_ok),
    .retrain(retrain), .dir_retrain(rt_s[1]), .dir_hot_reset(hr_s[1]),
    .link_up(link_up), .l0(l0), .state(ltssm), .recoveries(recoveries)
  );

  pcie_dll u_dll (
    .clk(pclk), .rst(prst), .link_up(link_up), .l0(l0),
    .d_data(d_data), .d_k(d_k), .d_err(d_err), .d_en(d_en),
    .l_data(l_data), .l_k(l_k), .l_busy(l_busy), .l_ok(l_ok), .retrain(retrain),
    .t_valid(t_valid), .t_hdr(ur_go ? ur_hdr : q_hdr), .t_dat(q_wd), .t_wd(!ur_go && q_wr),
    .t_fc(ur_go ? 2'd2 : q_wr && !q_cfg ? 2'd0 : 2'd1), .t_ready(t_ready),
    .r_valid(r_valid), .r_tlp(r_tlp), .r_ndw(r_ndw),
    .np_free(np_free), .np_free_d(np_free_d),
    .dl_up(dl_up), .replays(replays), .e_tlp(e_tlp), .e_dllp(e_dllp), .e_rx(e_rx)
  );
endmodule
