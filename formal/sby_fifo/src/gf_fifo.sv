// =============================================================================
// gf_fifo - Generic synchronous FIFO, valid/ready both sides
// Copyright (c) 2026 Verily. All rights reserved.
// Used for: command_fifo, completion_queue storage, result_fifo.
// =============================================================================
module gf_fifo #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned DEPTH  = 4
) (
  input  logic              clk_i,
  input  logic              rst_ni,

  input  logic              valid_i,
  output logic              ready_o,
  input  logic [DATA_W-1:0] data_i,

  output logic              valid_o,
  input  logic              ready_i,
  output logic [DATA_W-1:0] data_o,

  output logic [$clog2(DEPTH+1)-1:0] count_o
);

  localparam int unsigned PTR_W = $clog2(DEPTH);

  logic [DATA_W-1:0] mem [DEPTH];
  logic [PTR_W-1:0]  wptr_q, rptr_q;
  logic [$clog2(DEPTH+1)-1:0] cnt_q;

  wire wr = valid_i && ready_o;
  wire rd = valid_o && ready_i;

  assign ready_o = (cnt_q != $bits(cnt_q)'(DEPTH));
  assign valid_o = (cnt_q != '0);
  assign data_o  = mem[rptr_q];
  assign count_o = cnt_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wptr_q <= '0;
      rptr_q <= '0;
      cnt_q  <= '0;
    end else begin
      if (wr) begin
        mem[wptr_q] <= data_i;
        wptr_q <= (wptr_q == PTR_W'(DEPTH-1)) ? '0 : wptr_q + 1'b1;
      end
      if (rd) begin
        rptr_q <= (rptr_q == PTR_W'(DEPTH-1)) ? '0 : rptr_q + 1'b1;
      end
      unique case ({wr, rd})
        2'b10: cnt_q <= cnt_q + 1'b1;
        2'b01: cnt_q <= cnt_q - 1'b1;
        default: ;
      endcase
    end
  end

`ifdef GF_ASSERTIONS
  a_no_overflow:  assert property (@(posedge clk_i) disable iff (!rst_ni)
    valid_i |-> ready_o || !wr);
  a_no_underflow: assert property (@(posedge clk_i) disable iff (!rst_ni)
    rd |-> cnt_q != '0);
`endif

endmodule
