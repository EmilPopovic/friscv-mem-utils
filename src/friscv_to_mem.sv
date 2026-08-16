// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>

/*
 * Bridge between a FRISC-V memory subordinate port and a PULP mem manager port.
 * Single-beat transfers only, bursts are not supported and burst is ignored.
 */

module friscv_to_mem
    import friscv_mem_pkg::*;
#(
    parameter bit RegisterReq = 1'b0
) (
    input  logic            clk_i,
    input  logic            rst_ni,

    output logic            req_o,
    output logic [31:0]     addr_o,
    output logic            we_o,
    output logic [31:0]     wdata_o,
    output logic [3:0]      be_o,
    input  logic            gnt_i,
    input  logic            rvalid_i,
    input  logic            err_i,
    input  logic            other_err_i,
    input  logic [31:0]     rdata_i,

    input  friscv_mem_req_t s_req_i,
    output friscv_mem_rsp_t s_rsp_o
);

typedef enum logic [1:0] {
    S_IDLE,
    S_REQ,
    S_RSP
} state_e;

state_e state_q, state_d;

logic [31:0] addr_q;
logic [31:0] wdata_q;
logic [1:0]  size_q;
logic        we_q;

logic w_issue;
assign w_issue = !RegisterReq && (state_q == S_IDLE) && s_req_i.en;

logic [1:0] w_size;
assign w_size = w_issue ? s_req_i.size : size_q;

logic [3:0] base_be;
always_comb begin
    case (w_size)
        SIZE_BYTE: base_be = 4'b0001;
        SIZE_HALF: base_be = 4'b0011;
        SIZE_WORD: base_be = 4'b1111;
        default:   base_be = 4'b1111;
    endcase
end

assign addr_o  = w_issue ? s_req_i.addr  : addr_q;
assign we_o    = w_issue ? s_req_i.wr    : we_q;
assign wdata_o = w_issue ? s_req_i.wdata : wdata_q;
assign be_o    = base_be << addr_o[1:0];

logic w_completing;
assign w_completing = (state_q == S_RSP) && rvalid_i;

assign s_rsp_o.rdata = rdata_i;
assign s_rsp_o.err   = w_completing && (err_i || other_err_i);
assign s_rsp_o.stall = (state_q == S_RSP) ? !rvalid_i : 1'b1;
assign s_rsp_o.beat  = 1'b0;

assign req_o = w_issue || (state_q == S_REQ);

always_comb begin
    state_d = state_q;
    case (state_q)
        S_IDLE:  if (s_req_i.en) state_d = (w_issue && gnt_i) ? S_RSP : S_REQ;
        S_REQ:   if (gnt_i)      state_d = S_RSP;
        S_RSP:   if (rvalid_i)   state_d = S_IDLE;
        default: state_d = S_IDLE;
    endcase
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        state_q <= S_IDLE;
        addr_q  <= '0;
        wdata_q <= '0;
        size_q  <= SIZE_WORD;
        we_q    <= 1'b0;
    end else begin
        state_q <= state_d;
        if (state_q == S_IDLE) begin
            addr_q  <= s_req_i.addr;
            wdata_q <= s_req_i.wdata;
            size_q  <= s_req_i.size;
            we_q    <= s_req_i.en && s_req_i.wr;
        end
    end
end

endmodule
