// Asynchronous FIFO, 2^A entries. Gray-coded pointers, two-flop synchronizers.
module async_fifo #(parameter W = 8, A = 2) (
  input          wclk,
  input          wrst,
  input          winc,
  input  [W-1:0] wdata,
  output         wfull,
  input          rclk,
  input          rrst,
  input          rinc,
  output [W-1:0] rdata,
  output         rempty
);
  reg [W-1:0] mem [0:(1<<A)-1];
  reg   [A:0] wbin, wgray, rbin, rgray;
  reg   [A:0] rgray_w1, rgray_w2;   // read pointer in the write domain
  reg   [A:0] wgray_r1, wgray_r2;   // write pointer in the read domain

  wire [A:0] wbin_n  = wbin + (winc && !wfull);
  wire [A:0] rbin_n  = rbin + (rinc && !rempty);
  assign wfull  = wgray == {~rgray_w2[A:A-1], rgray_w2[A-2:0]};
  assign rempty = rgray == wgray_r2;
  assign rdata  = mem[rbin[A-1:0]];

  always @(posedge wclk) begin
    if (winc && !wfull) mem[wbin[A-1:0]] <= wdata;
    if (wrst) begin
      wbin <= 0; wgray <= 0; rgray_w1 <= 0; rgray_w2 <= 0;
    end else begin
      wbin  <= wbin_n;
      wgray <= wbin_n ^ (wbin_n >> 1);
      {rgray_w2, rgray_w1} <= {rgray_w1, rgray};
    end
  end

  always @(posedge rclk)
    if (rrst) begin
      rbin <= 0; rgray <= 0; wgray_r1 <= 0; wgray_r2 <= 0;
    end else begin
      rbin  <= rbin_n;
      rgray <= rbin_n ^ (rbin_n >> 1);
      {wgray_r2, wgray_r1} <= {wgray_r1, wgray};
    end
endmodule
