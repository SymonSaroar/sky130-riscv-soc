// 8b/10b, shared by the PHY and lane models. Codes are {abcdei, fghj} with a in bit 9, the first bit on the line.
localparam [7:0] COM = 8'hBC, SKP = 8'h1C, IDL = 8'h7C, EDB = 8'hFE, STP = 8'hFB, SDP = 8'h5C, END = 8'hFD;
localparam [9:0] COM_N = 10'b0011111010, COM_P = 10'b1100000101;

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
initial begin : build_dtab
  integer c, v; reg [10:0] e;
  for (c = 0; c < 1024; c = c + 1) dtab[c] = 10'b0;
  for (v = 0; v < 512; v = v + 1)
    if (!v[8] || v[4:0] == 28 || (v[7:5] == 7 && (v[4:0] == 23 || v[4:0] == 27 || v[4:0] == 29 || v[4:0] == 30))) begin
      e = enc(v[8], v[7:0], 1'b0); dtab[e[9:0]] = {1'b1, v[8], v[7:0]};
      e = enc(v[8], v[7:0], 1'b1); dtab[e[9:0]] = {1'b1, v[8], v[7:0]};
    end
end
