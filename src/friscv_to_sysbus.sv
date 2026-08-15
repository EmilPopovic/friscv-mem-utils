// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>

module friscv_to_sysbus import friscv_mem_pkg::*; #(
    parameter type sys_req_t  = friscv_sysbus_pkg::sys_req_t,
    parameter type sys_resp_t = friscv_sysbus_pkg::sys_resp_t
) (
    input  logic            clk_i,
    input  logic            rst_ni,

    input  friscv_mem_req_t s_req_i,
    output friscv_mem_rsp_t s_rsp_o,

    output sys_req_t        m_sys_req,
    input  sys_resp_t       m_sys_resp
);

logic r_active;
logic r_rdy_prev;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        r_active   <= 1'b0;
        r_rdy_prev <= 1'b0;
    end else begin
        r_rdy_prev <= m_sys_resp.rdy;

        if (s_req_i.en && !r_active)
            r_active <= 1'b1;
        else if (r_active && m_sys_resp.rdy && r_rdy_prev)
            r_active <= 1'b0;
    end
end

assign m_sys_req.en   = s_req_i.en && !r_active;
assign s_rsp_o.stall  = s_req_i.en && !(r_active && m_sys_resp.rdy && r_rdy_prev);

// Passthrough signals
assign m_sys_req.addr  = s_req_i.addr;
assign m_sys_req.wdata = s_req_i.wdata;
assign s_rsp_o.rdata   = m_sys_resp.rdata;
assign s_rsp_o.err     = m_sys_resp.err;

// Generate strobe from size and address
logic [3:0] base_strb;
always_comb begin
    case (s_req_i.size)
        SIZE_BYTE: base_strb = 4'b0001;
        SIZE_HALF: base_strb = 4'b0011;
        SIZE_WORD: base_strb = 4'b1111;
        default:   base_strb = 4'b1111;
    endcase
end

logic [1:0] byte_offset;
assign byte_offset = s_req_i.addr[1:0];

logic [3:0] shifted_strb;
assign shifted_strb = base_strb << byte_offset;

assign m_sys_req.we = (s_req_i.en && s_req_i.wr) ? shifted_strb : 4'h0;

// Tie off unused signals
assign s_rsp_o.beat = 1'b0;

endmodule
