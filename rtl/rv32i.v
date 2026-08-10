// RV32IM + Zicsr core. Stages: IF (SRAM read port), ID (instruction register), EX, WB (bus response).
// Instruction fetch reads the SRAM read port directly; data goes over AXI4-Lite.
module rv32i (
  input             clk,
  input             rst,
  // instruction port: synchronous SRAM, data returns the cycle after i_addr
  output     [31:0] i_addr,
  input      [31:0] i_rdata,
  input             i_valid,      // i_rdata holds the word at the previous i_addr
  // AXI4-Lite master (one transaction in flight)
  output     [31:0] m_awaddr,
  output            m_awvalid,
  input             m_awready,
  output     [31:0] m_wdata,
  output      [3:0] m_wstrb,
  output            m_wvalid,
  input             m_wready,
  input             m_bvalid,
  output            m_bready,
  output     [31:0] m_araddr,
  output            m_arvalid,
  input             m_arready,
  input      [31:0] m_rdata,
  input             m_rvalid,
  output            m_rready,
  // interrupts
  input             irq_timer,
  input             irq_ext
);
  localparam RESET_PC = 32'h0;

  // ---------------- fetch: the SRAM returns the word at f_pc this cycle ----------------
  reg         f_valid;
  reg  [31:0] f_pc;

  // ---------------- EX stage ----------------
  reg         e_valid;
  reg  [31:0] pc;
  reg  [31:0] ins;

  wire [6:0] op     = ins[6:0];
  wire [4:0] rd     = ins[11:7];
  wire [2:0] f3     = ins[14:12];
  wire [4:0] rs1    = ins[19:15];
  wire [4:0] rs2    = ins[24:20];
  wire       f7     = ins[30];

  wire is_lui    = op == 7'b0110111;
  wire is_auipc  = op == 7'b0010111;
  wire is_jal    = op == 7'b1101111;
  wire is_jalr   = op == 7'b1100111;
  wire is_branch = op == 7'b1100011;
  wire is_load   = op == 7'b0000011;
  wire is_store  = op == 7'b0100011;
  wire is_opimm  = op == 7'b0010011;
  wire is_op     = op == 7'b0110011;
  wire is_system = op == 7'b1110011;
  wire is_csr    = is_system && f3 != 3'b000;
  wire is_mret   = is_system && f3 == 3'b000 && ins[29:28] == 2'b11;

  wire [31:0] imm_i = {{21{ins[31]}}, ins[30:20]};
  wire [31:0] imm_s = {{21{ins[31]}}, ins[30:25], ins[11:7]};
  wire [31:0] imm_b = {{20{ins[31]}}, ins[7], ins[30:25], ins[11:8], 1'b0};
  wire [31:0] imm_u = {ins[31:12], 12'b0};
  wire [31:0] imm_j = {{12{ins[31]}}, ins[19:12], ins[20], ins[30:21], 1'b0};

  // ---------------- register file ----------------
  reg  [31:0] rf [0:31];      // entry 0 is never written

  // WB stage: waits for the bus response of a load or store
  reg         w_busy, w_load;
  reg   [4:0] w_rd;
  reg   [2:0] w_f3;
  reg   [1:0] w_off;
  wire        w_done = w_busy && (w_load ? m_rvalid : m_bvalid);

  wire [31:0] ld_sh = m_rdata >> {w_off, 3'b0};
  wire [31:0] ld_data =
      w_f3 == 3'b000 ? {{24{ld_sh[7]}},  ld_sh[7:0]}  :
      w_f3 == 3'b001 ? {{16{ld_sh[15]}}, ld_sh[15:0]} :
      w_f3 == 3'b100 ? {24'b0, ld_sh[7:0]}            :
      w_f3 == 3'b101 ? {16'b0, ld_sh[15:0]}           : ld_sh;
  wire        ld_we = w_done && w_load && w_rd != 0;

  wire [31:0] x1 = rs1 == 0 ? 32'b0 : rf[rs1];
  wire [31:0] x2 = rs2 == 0 ? 32'b0 : rf[rs2];
  // EX waits one cycle for a register that a load in WB is writing
  wire        ld_use = w_busy && w_load && w_rd != 0 && (w_rd == rs1 || w_rd == rs2);

  // ---------------- ALU ----------------
  wire [31:0] b    = is_op ? x2 : imm_i;
  wire        sub  = is_op && f7;
  wire [31:0] sum  = x1 + (sub ? ~b : b) + sub;
  wire        lt   = $signed(x1) < $signed(b);
  wire        ltu  = x1 < b;
  wire [4:0]  sh   = b[4:0];
  wire [31:0] sra  = $signed(x1) >>> sh;
  reg  [31:0] alu;
  always @* case (f3)
    3'b000: alu = sum;
    3'b001: alu = x1 << sh;
    3'b010: alu = {31'b0, lt};
    3'b011: alu = {31'b0, ltu};
    3'b100: alu = x1 ^ b;
    3'b101: alu = f7 ? sra : x1 >> sh;
    3'b110: alu = x1 | b;
    default: alu = x1 & b;
  endcase

  reg br;
  always @* case (f3)
    3'b000: br = x1 == x2;
    3'b001: br = x1 != x2;
    3'b100: br = $signed(x1) <  $signed(x2);
    3'b101: br = $signed(x1) >= $signed(x2);
    3'b110: br = x1 <  x2;
    3'b111: br = x1 >= x2;
    default: br = 1'b0;
  endcase

  // ---------------- M extension ----------------
  wire        is_m   = is_op && ins[25];
  wire        is_div = is_m && f3[2];
  wire        hold   = (w_busy && !w_done) || ld_use;   // operands not ready
  // multiply: rs1 signed for MUL/MULH/MULHSU, rs2 signed for MUL/MULH
  wire signed [32:0] ma = {f3[1:0] != 2'b11 && x1[31], x1};
  wire signed [32:0] mb = {!f3[1] && x2[31], x2};
  wire signed [65:0] mp = ma * mb;
  // divide: 32 iterations of restoring division on magnitudes
  wire        d_s   = !f3[0];
  wire        neg_a = d_s && x1[31];
  wire        neg_b = d_s && x2[31];
  reg  [31:0] dq, dr, dd;
  reg   [5:0] dcnt;
  reg         d_busy, d_done;
  wire [32:0] dt    = {dr, dq[31]} - {1'b0, dd};
  wire [31:0] quo   = neg_a != neg_b && x2 != 0 ? -dq : dq;
  wire [31:0] rem   = neg_a ? -dr : dr;
  wire [31:0] m_res = is_div ? (f3[1] ? rem : quo) : f3[1:0] == 2'b00 ? mp[31:0] : mp[63:32];

  // ---------------- CSRs ----------------
  reg        mie_g, mpie;          // mstatus.MIE, mstatus.MPIE
  reg        mtie, meie;           // mie.MTIE, mie.MEIE
  reg [31:0] mtvec, mepc, mcause;
  wire [31:0] mstatus = {24'b0, mpie, 3'b0, mie_g, 3'b0};
  wire [31:0] mie_r   = {20'b0, meie, 3'b0, mtie, 7'b0};
  wire [31:0] mip_r   = {20'b0, irq_ext, 3'b0, irq_timer, 7'b0};

  wire [11:0] csr_a = ins[31:20];
  reg  [31:0] csr_r;
  always @* case (csr_a)
    12'h300: csr_r = mstatus;
    12'h304: csr_r = mie_r;
    12'h305: csr_r = mtvec;
    12'h341: csr_r = mepc;
    12'h342: csr_r = mcause;
    12'h344: csr_r = mip_r;
    default: csr_r = 32'b0;
  endcase
  wire [31:0] csr_src = f3[2] ? {27'b0, rs1} : x1;
  wire [31:0] csr_w = f3[1:0] == 2'b01 ? csr_src :
                      f3[1:0] == 2'b10 ? csr_r | csr_src : csr_r & ~csr_src;

  // ---------------- memory requests ----------------
  wire        mem   = is_load || is_store;
  wire [31:0] maddr = x1 + (is_store ? imm_s : imm_i);
  // interrupts are taken on a non-memory, non-divide instruction once WB is free
  wire        irq   = mie_g && ((irq_timer && mtie) || (irq_ext && meie)) &&
                      (!w_busy || (w_done && !ld_use)) && !mem && !is_div;
  wire        go    = e_valid && !irq;          // EX instruction executes
  wire        req   = go && mem && !w_busy;
  wire        req_ok = is_load ? m_arready : m_awready && m_wready;

  assign m_araddr  = maddr;
  assign m_arvalid = req && is_load;
  assign m_awaddr  = maddr;
  assign m_awvalid = req && is_store;
  assign m_wvalid  = req && is_store;
  assign m_wdata   = x2 << {maddr[1:0], 3'b0};
  assign m_wstrb   = (f3[1:0] == 2'b00 ? 4'b0001 :
                      f3[1:0] == 2'b01 ? 4'b0011 : 4'b1111) << maddr[1:0];
  assign m_rready  = 1'b1;
  assign m_bready  = 1'b1;

  wire stall = e_valid && ((w_busy && !w_done) || ld_use || (mem && !(req && req_ok)) || (is_div && !d_done));
  wire adv   = go && !stall;                    // EX instruction retires

  // ---------------- next PC ----------------
  wire        taken  = is_jal || is_jalr || (is_branch && br);
  wire [31:0] target = is_jalr ? {sum[31:1], 1'b0} : pc + (is_jal ? imm_j : imm_b);
  wire [31:0] pc4    = pc + 4;

  wire redirect = e_valid && (irq || (!stall && (is_mret || taken)));
  assign i_addr = !f_valid ? RESET_PC :
                  redirect ? (irq ? mtvec : is_mret ? mepc : target) :
                  stall || !i_valid ? f_pc : f_pc + 4;

  // ---------------- writeback from EX ----------------
  wire        e_we = adv && rd != 0 && (is_lui || is_auipc || is_jal || is_jalr || is_opimm || is_op || is_csr);
  wire [31:0] e_wd = is_lui            ? imm_u :
                     is_auipc          ? pc + imm_u :
                     is_jal || is_jalr ? pc4 :
                     is_csr            ? csr_r :
                     is_m              ? m_res : alu;

  integer i;
  always @(posedge clk) begin
    for (i = 1; i < 32; i = i + 1) begin
      if (e_we && rd == i)       rf[i] <= e_wd;
      else if (ld_we && w_rd == i) rf[i] <= ld_data;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      f_valid <= 1'b0;
      e_valid <= 1'b0;
      w_busy  <= 1'b0;
      d_busy  <= 1'b0;
      d_done  <= 1'b0;
      mie_g   <= 1'b0;
      mpie    <= 1'b0;
      mtie    <= 1'b0;
      meie    <= 1'b0;
      mtvec   <= 32'b0;
      mepc    <= 32'b0;
      mcause  <= 32'b0;
    end else begin
      f_valid <= 1'b1;
      f_pc    <= i_addr;
      if (!stall) begin
        ins     <= i_rdata;
        pc      <= f_pc;
        e_valid <= f_valid && !redirect && i_valid;
      end

      if (e_valid && is_div && !d_busy && !d_done && !hold) begin
        dq <= neg_a ? -x1 : x1;
        dd <= neg_b ? -x2 : x2;
        dr <= 32'b0;
        dcnt <= 6'd32;
        d_busy <= 1'b1;
      end else if (d_busy) begin
        dr <= dt[32] ? {dr[30:0], dq[31]} : dt[31:0];
        dq <= {dq[30:0], !dt[32]};
        dcnt <= dcnt - 1;
        if (dcnt == 1) begin d_busy <= 1'b0; d_done <= 1'b1; end
      end else if (adv) d_done <= 1'b0;

      if (w_done) w_busy <= 1'b0;
      if (adv && mem) begin
        w_busy <= 1'b1;
        w_load <= is_load;
        w_rd   <= rd;
        w_f3   <= f3;
        w_off  <= maddr[1:0];
      end

      if (e_valid && irq) begin
        mepc   <= pc;
        mcause <= irq_ext && meie ? 32'h8000000b : 32'h80000007;
        mpie   <= mie_g;
        mie_g  <= 1'b0;
      end else if (adv && is_mret) begin
        mie_g  <= mpie;
        mpie   <= 1'b1;
      end else if (adv && is_csr) begin
        case (csr_a)
          12'h300: begin mie_g <= csr_w[3]; mpie <= csr_w[7]; end
          12'h304: begin mtie <= csr_w[7]; meie <= csr_w[11]; end
          12'h305: mtvec  <= {csr_w[31:2], 2'b0};
          12'h341: mepc   <= {csr_w[31:2], 2'b0};
          12'h342: mcause <= csr_w;
          default: ;
        endcase
      end
    end
  end
endmodule
