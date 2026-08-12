// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>

module friscv_to_sysbus import friscv_mem_pkg::*, friscv_sysbus_pkg::*; #(
    parameter type sys_req_t  = friscv_sysbus_pkg::sys_req_t,
    parameter type sys_resp_t = friscv_sysbus_pkg::sys_resp_t
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    friscv_mem_if.slave s_mem,
    output sys_req_t    m_sys_req,
    input  sys_resp_t   m_sys_resp
);

logic r_active;
logic r_rdy_prev;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        r_active   <= 1'b0;
        r_rdy_prev <= 1'b0;
    end else begin
        r_rdy_prev <= m_sys_resp.rdy;

        if (s_mem.rw != RW_IDLE && !r_active)
            r_active <= 1'b1;
        else if (r_active && m_sys_resp.rdy && r_rdy_prev)
            r_active <= 1'b0;
    end
end

assign m_sys_req.en = (s_mem.rw != RW_IDLE) && !r_active;
assign s_mem.wait_req = (s_mem.rw != RW_IDLE) && !(r_active && m_sys_resp.rdy && r_rdy_prev);

// Passthrough signals
assign m_sys_req.addr  = s_mem.addr;
assign m_sys_req.wdata = s_mem.wdata;
assign s_mem.rdata     = m_sys_resp.rdata;
assign s_mem.err       = m_sys_resp.err;

// Generate strobe from size and address
logic [3:0] base_strb;
always_comb begin
    case (s_mem.size)
        WIDTH_I8, WIDTH_U8:   base_strb = 4'b0001;
        WIDTH_I16, WIDTH_U16: base_strb = 4'b0011;
        WIDTH_I32:            base_strb = 4'b1111;
        default:              base_strb = 4'b1111;
    endcase
end

logic [1:0] byte_offset;
assign byte_offset = s_mem.addr[1:0];

logic [3:0] shifted_strb;
assign shifted_strb = base_strb << byte_offset;

assign m_sys_req.we = (s_mem.rw == RW_WRITE) ? shifted_strb : 4'h0;

// Tie off unused signals
assign s_mem.beat_valid = 1'b0;

endmodule
