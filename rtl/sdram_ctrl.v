// SDR SDRAM controller, 16-bit device, 4 banks x 8192 rows x 512 columns.
// One 32-bit word per access: burst of 2 with auto-precharge. All pins registered.
// Word address map: row = w[22:10], bank = w[9:8], column = {w[7:0], beat}.
module sdram_ctrl #(
  parameter CL     = 3,
  parameter T_INIT = 10000,   // power-up wait, cycles (100 us at 100 MHz)
  parameter T_RP   = 2,
  parameter T_RCD  = 2,
  parameter T_RFC  = 7,
  parameter T_MRD  = 2,
  parameter T_WR   = 2,
  parameter T_REFI = 750      // refresh interval, cycles
) (
  input             clk,
  input             rst,
  // command in: {we, word address, wdata, wstrb}
  input             c_valid,
  input      [59:0] c_data,
  output            c_pop,
  // response out: read data (0 for writes)
  output reg        r_push,
  output reg [31:0] r_data,
  // pins
  output reg        cke,
  output reg        cs_n,
  output reg        ras_n,
  output reg        cas_n,
  output reg        we_n,
  output reg  [1:0] ba,
  output reg [12:0] a,
  output reg  [1:0] dqm,
  output reg [15:0] dq_out,
  output reg        dq_oe,
  input      [15:0] dq_in
);
  localparam [3:0] NOP = 4'b0111, ACT = 4'b0011, READ = 4'b0101, WRITE = 4'b0100,
                   PRE = 4'b0010, REF = 4'b0001, MRS = 4'b0000;
  localparam [2:0]  CLB  = CL;
  localparam [12:0] MODE = {6'b0, CLB, 4'b0001};             // burst 2, sequential

  localparam [2:0] S_INIT = 0, S_REF1 = 1, S_REF2 = 2, S_MRS = 3, S_IDLE = 4, S_RW = 5, S_WR2 = 6;
  reg  [2:0] st;
  reg [13:0] cnt;
  reg  [9:0] refcnt;
  reg        ref_req;

  reg        we;
  reg [22:0] w;
  reg [31:0] wd;
  reg  [3:0] ws;

  reg [15:0] dq_q;                 // read data, one cycle after the falling-edge capture
  reg [CL+4:0] rdv;                // read issued, shifted once per cycle
  reg [15:0] lo;

  wire done_wait = cnt == 0;
  assign c_pop = st == S_IDLE && done_wait && !ref_req && c_valid;

  task cmd(input [3:0] c); {cs_n, ras_n, cas_n, we_n} <= c; endtask

  always @(posedge clk) begin
    dq_q   <= dq_in;
    rdv    <= {rdv[CL+3:0], 1'b0};
    r_push <= 1'b0;
    cmd(NOP);
    dq_oe  <= 1'b0;

    if (rst) begin
      st      <= S_INIT;
      cnt     <= T_INIT;
      cke     <= 1'b0;
      refcnt  <= T_REFI;
      ref_req <= 1'b0;
      rdv     <= 0;
    end else begin
      cke <= 1'b1;
      if (!done_wait) cnt <= cnt - 1;

      if (refcnt == 0) begin refcnt <= T_REFI; ref_req <= 1'b1; end
      else refcnt <= refcnt - 1;

      // read data: beat 0 then beat 1
      if (rdv[CL+3]) lo <= dq_q;
      if (rdv[CL+4]) begin r_push <= 1'b1; r_data <= {dq_q, lo}; end

      if (done_wait) case (st)
        S_INIT: begin cmd(PRE); a <= 13'h400; cnt <= T_RP - 1;  st <= S_REF1; end
        S_REF1: begin cmd(REF); cnt <= T_RFC - 1; st <= S_REF2; end
        S_REF2: begin cmd(REF); cnt <= T_RFC - 1; st <= S_MRS; end
        S_MRS:  begin cmd(MRS); ba <= 2'b0; a <= MODE; cnt <= T_MRD - 1; st <= S_IDLE; ref_req <= 1'b0; end
        S_IDLE:
          if (ref_req) begin
            cmd(REF); cnt <= T_RFC - 1; ref_req <= 1'b0;
          end else if (c_valid) begin
            {we, w, wd, ws} <= c_data;
            cmd(ACT); ba <= c_data[45:44]; a <= c_data[58:46];
            cnt <= T_RCD - 1; st <= S_RW;
          end
        S_RW: begin
          a <= {4'b0010, w[7:0], 1'b0};
          if (we) begin
            cmd(WRITE); dq_out <= wd[15:0]; dqm <= ~ws[1:0]; dq_oe <= 1'b1; st <= S_WR2;
          end else begin
            cmd(READ); dqm <= 2'b00; rdv[0] <= 1'b1; cnt <= CL + 3; st <= S_IDLE;
          end
        end
        S_WR2: begin
          dq_out <= wd[31:16]; dqm <= ~ws[3:2]; dq_oe <= 1'b1;
          r_push <= 1'b1; r_data <= 32'b0;
          cnt <= T_WR + T_RP; st <= S_IDLE;
        end
        default: st <= S_INIT;
      endcase
    end
  end
endmodule
