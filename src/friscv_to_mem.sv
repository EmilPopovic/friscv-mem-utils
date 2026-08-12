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
 * Bridge between a friscv_mem_if master interface and a Pulp mem master port.
 * Single-beat transfers only, bursts are not supported and burst_en is ignored.
 */

module friscv_to_mem import friscv_mem_pkg::*; #(
    parameter bit RegisterReq = 1'b0
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    output logic        req_o,
    output addr_t       addr_o,
    output logic        we_o,
    output data_t       wdata_o,
    output logic [3:0]  be_o,
    input  logic        gnt_i,
    input  logic        rvalid_i,
    input  logic        err_i,
    input  logic        other_err_i,
    input  data_t       rdata_i,

    friscv_mem_if.slave s_mem
);

typedef enum logic [1:0] {
    S_IDLE,
    S_REQ,
    S_RSP
} state_e;

state_e state_q, state_d;

addr_t      addr_q;
data_t      wdata_q;
mem_width_e size_q;
logic       we_q;

logic w_issue;
assign w_issue = !RegisterReq && (state_q == S_IDLE) && (s_mem.rw != RW_IDLE);

mem_width_e w_size;
assign w_size = w_issue ? s_mem.size : size_q;

logic [3:0] base_be;
always_comb begin
    case (w_size)
        WIDTH_I8, WIDTH_U8:   base_be = 4'b0001;
        WIDTH_I16, WIDTH_U16: base_be = 4'b0011;
        WIDTH_I32:            base_be = 4'b1111;
        default:              base_be = 4'b1111;
    endcase
end

assign addr_o  = w_issue ? s_mem.addr : addr_q;
assign we_o    = w_issue ? (s_mem.rw == RW_WRITE) : we_q;
assign wdata_o = w_issue ? s_mem.wdata : wdata_q;
assign be_o    = base_be << addr_o[1:0];

logic w_completing;
assign w_completing = (state_q == S_RSP) && rvalid_i;

assign s_mem.rdata      = rdata_i;
assign s_mem.err        = w_completing && (err_i || other_err_i);
assign s_mem.wait_req   = (state_q == S_RSP) ? !rvalid_i : 1'b1;
assign s_mem.beat_valid = 1'b0;

assign req_o = w_issue || (state_q == S_REQ);

always_comb begin
    state_d = state_q;
    case (state_q)
        S_IDLE:  if (s_mem.rw != RW_IDLE) state_d = (w_issue && gnt_i) ? S_RSP : S_REQ;
        S_REQ:   if (gnt_i)                 state_d = S_RSP;
        S_RSP:   if (rvalid_i)              state_d = S_IDLE;
        default: state_d = S_IDLE;
    endcase
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        state_q <= S_IDLE;
        addr_q  <= '0;
        wdata_q <= '0;
        size_q  <= WIDTH_I32;
        we_q    <= 1'b0;
    end else begin
        state_q <= state_d;
        if (state_q == S_IDLE) begin
            addr_q  <= s_mem.addr;
            wdata_q <= s_mem.wdata;
            size_q  <= s_mem.size;
            we_q    <= s_mem.rw == RW_WRITE;
        end
    end
end

endmodule
