// SDR SDRAM model, 16-bit, 4 banks x 8192 rows x 512 columns.
// Read data appears tAC after the clock, CL clocks after READ. Counts protocol errors.
`timescale 1ns/1ps
module sdram_model (
  input         clk,
  input         cke,
  input         cs_n,
  input         ras_n,
  input         cas_n,
  input         we_n,
  input   [1:0] ba,
  input  [12:0] a,
  input   [1:0] dqm,
  inout  [15:0] dq
);
  localparam T_AC = 5.4, T_REFI_MAX = 7800;
  reg [15:0] mem [0:(1<<24)-1];
  reg [12:0] row [0:3];
  reg  [3:0] open;
  integer    act_t [0:3];
  integer    cyc = 0, errors = 0, cl = 0, bl = 0, last_ref = 0, i;
  reg        moded = 0;

  // read pipeline, indexed by cycle
  reg [15:0] rd_q [0:7];
  reg  [7:0] rd_v = 0;
  reg [15:0] dq_r;
  reg        dq_en = 0;
  assign dq = dq_en ? dq_r : 16'bz;

  // write burst in progress
  integer    wr_left = 0;
  reg [23:0] wr_addr;

  task error(input [8*40-1:0] msg);
    begin errors = errors + 1; $display("%0t SDRAM ERROR: %0s", $time, msg); end
  endtask

  always @(posedge clk) if (cke) begin
    cyc = cyc + 1;

    // data out for reads issued CL clocks ago
    rd_v = rd_v >> 1;
    for (i = 0; i < 7; i = i + 1) rd_q[i] = rd_q[i + 1];
    if (rd_v[0]) begin dq_r <= #(T_AC) rd_q[0]; dq_en <= #(T_AC) 1'b1; end
    else dq_en <= #(T_AC) 1'b0;

    if (wr_left > 0) begin
      if (!dqm[0]) mem[wr_addr][7:0]  = dq[7:0];
      if (!dqm[1]) mem[wr_addr][15:8] = dq[15:8];
      wr_addr = wr_addr + 1;
      wr_left = wr_left - 1;
    end

    if (!cs_n) case ({ras_n, cas_n, we_n})
      3'b011: begin                                      // ACT
        if (!moded) error("ACT before mode register set");
        if (open[ba]) error("ACT on an open bank");
        open[ba] = 1'b1; row[ba] = a; act_t[ba] = cyc;
      end
      3'b101, 3'b100: begin                              // READ, WRITE
        if (!open[ba]) error("access to a closed bank");
        if (cyc - act_t[ba] < 2) error("tRCD");
        if (we_n) begin
          for (i = 0; i < bl; i = i + 1) begin
            rd_q[cl + i] = mem[{ba, row[ba], a[8:0]} + i];
            rd_v[cl + i] = 1'b1;
          end
        end else begin
          wr_addr = {ba, row[ba], a[8:0]};
          if (!dqm[0]) mem[wr_addr][7:0]  = dq[7:0];
          if (!dqm[1]) mem[wr_addr][15:8] = dq[15:8];
          wr_addr = wr_addr + 1;
          wr_left = bl - 1;
        end
        if (a[10]) open[ba] = 1'b0;
      end
      3'b010: if (a[10]) open = 0; else open[ba] = 1'b0;   // PRECHARGE
      3'b001: begin                                      // REFRESH
        if (open != 0) error("REFRESH with an open bank");
        if (moded && $time - last_ref > T_REFI_MAX) error("refresh interval");
        last_ref = $time;
      end
      3'b000: begin                                      // MODE REGISTER SET
        if (open != 0) error("MRS with an open bank");
        cl = a[6:4]; bl = 1 << a[2:0]; moded = 1;
        last_ref = $time;
      end
      default: ;
    endcase
  end

  initial begin
    open = 0;
    for (i = 0; i < 8; i = i + 1) rd_q[i] = 0;
  end
endmodule
