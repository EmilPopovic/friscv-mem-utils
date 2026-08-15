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
 * This module implements an adapter between the FRISC-V memory protocol and a full AXI4 manager port.
 * It supports single-beat and burst transactions of BurstLen beats, which can be configured as needed.
 */

module friscv_to_axi4_full import friscv_mem_pkg::*; #(
    parameter int unsigned BurstLen = 8,
    parameter type axi_req_t = friscv_axi_pkg::axi_req_t,
    parameter type axi_rsp_t = friscv_axi_pkg::axi_resp_t
) (
    input  logic            clk_i,
    input  logic            rst_ni,

    input  friscv_mem_req_t s_req_i,
    output friscv_mem_rsp_t s_rsp_o,

    output axi_req_t        m_axi_req_o,
    input  axi_rsp_t        m_axi_rsp_i
);

typedef enum logic [2:0] {
    S_IDLE,
    S_W,
    S_W_RET,
    S_R_ADDR,
    S_R_DATA
} state_e;

state_e r_state, w_next_state;

// Latched transaction parameters
logic [1:0]  r_size;
logic        r_burst;
logic [31:0] r_addr;
logic [31:0] r_wdata, r_rdata;

logic r_aw_done, r_w_done;

// Count of beats in burst transactions
logic [4:0] r_count;

// Data width and alignment
logic [3:0] base_strb;
logic [1:0] byte_offset;
assign byte_offset = r_addr[1:0];

always_comb begin
    case (r_size)
        SIZE_BYTE: base_strb = 4'b0001;
        SIZE_HALF: base_strb = 4'b0011;
        SIZE_WORD: base_strb = 4'b1111;
        default:   base_strb = 4'b1111;
    endcase
end

logic [2:0] w_axsize;
always_comb begin
    case (r_size)
        SIZE_BYTE: w_axsize = 3'd0;
        SIZE_HALF: w_axsize = 3'd1;
        SIZE_WORD: w_axsize = 3'd2;
        default:   w_axsize = 3'd2;
    endcase
end

logic [7:0] w_axlen;
assign w_axlen = r_burst ? 8'(BurstLen - 1) : 8'h00;

logic w_read_completing, w_write_completing;
assign w_read_completing  = m_axi_rsp_i.r_valid && m_axi_req_o.r_ready;
assign w_write_completing = m_axi_rsp_i.b_valid && m_axi_req_o.b_ready;

assign s_rsp_o.rdata = w_read_completing ? m_axi_rsp_i.r.data : r_rdata;
assign s_rsp_o.stall = (r_state == S_W_RET)  ? !m_axi_rsp_i.b_valid :
                       (r_state == S_R_DATA) ? !(m_axi_rsp_i.r_valid && (!r_burst || m_axi_rsp_i.r.last)) : 1'b1;
assign s_rsp_o.beat  = r_burst &&
                       (((r_state == S_R_DATA) && m_axi_rsp_i.r_valid && m_axi_req_o.r_ready) ||
                        ((r_state == S_W)      && m_axi_req_o.w_valid && m_axi_rsp_i.w_ready));
assign s_rsp_o.err   = w_read_completing  ? |m_axi_rsp_i.r.resp :
                       w_write_completing ? |m_axi_rsp_i.b.resp : 1'b0;

// Clocked logic
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        r_burst   <= 1'b0;
        r_state   <= S_IDLE;
        r_aw_done <= 1'b0;
        r_w_done  <= 1'b0;
        r_count   <= '0;
        r_addr    <= '0;
        r_wdata   <= '0;
        r_rdata   <= '0;
        r_size    <= SIZE_WORD;
    end else begin
        r_state <= w_next_state;

        if (r_state == S_IDLE && s_req_i.en) begin
            r_addr    <= s_req_i.addr;
            r_wdata   <= s_req_i.wdata;
            r_size    <= s_req_i.size;
            r_burst   <= s_req_i.burst;
            r_aw_done <= 1'b0;
            r_w_done  <= 1'b0;
            r_count   <= '0;
        end

        if (r_state == S_W) begin
            if (m_axi_req_o.aw_valid && m_axi_rsp_i.aw_ready) r_aw_done <= 1'b1;
            if (m_axi_req_o.w_valid && m_axi_rsp_i.w_ready && m_axi_req_o.w.last) r_w_done <= 1'b1;

            if (r_burst && m_axi_req_o.w_valid && m_axi_rsp_i.w_ready) begin
                r_count <= r_count + 1'b1;
                r_wdata <= s_req_i.wdata;
            end
        end

        if (w_read_completing) r_rdata <= m_axi_rsp_i.r.data;
    end
end

always_comb begin
    w_next_state = r_state;

    m_axi_req_o = '0;

    // Write address channel
    m_axi_req_o.aw.id     = '0;
    m_axi_req_o.aw.addr   = r_addr;
    m_axi_req_o.aw.len    = w_axlen;
    m_axi_req_o.aw.size   = w_axsize;
    m_axi_req_o.aw.burst  = 2'b01;
    m_axi_req_o.aw.lock   = 1'b0;
    m_axi_req_o.aw.cache  = 4'b0011;
    m_axi_req_o.aw.prot   = 3'b000;
    m_axi_req_o.aw.qos    = 4'h0;
    m_axi_req_o.aw.region = '0;
    m_axi_req_o.aw.atop   = '0;
    m_axi_req_o.aw.user   = '0;

    // Write data channel
    m_axi_req_o.w.data = r_wdata;
    m_axi_req_o.w.strb = base_strb << byte_offset;
    m_axi_req_o.w.user = '0;

    // Read address channel
    m_axi_req_o.ar.id     = '0;
    m_axi_req_o.ar.addr   = r_addr;
    m_axi_req_o.ar.len    = w_axlen;
    m_axi_req_o.ar.size   = w_axsize;
    m_axi_req_o.ar.burst  = 2'b01;
    m_axi_req_o.ar.lock   = 1'b0;
    m_axi_req_o.ar.cache  = 4'b0011;
    m_axi_req_o.ar.prot   = 3'b000;
    m_axi_req_o.ar.qos    = 4'h0;
    m_axi_req_o.ar.region = '0;
    m_axi_req_o.ar.user   = '0;

    case (r_state)
        S_IDLE: begin
            if (s_req_i.en)
                w_next_state = s_req_i.wr ? S_W : S_R_ADDR;
        end

        S_W: begin
            m_axi_req_o.aw_valid = !r_aw_done;
            if (r_burst) begin
                m_axi_req_o.w_valid = !r_w_done && (32'(r_count) < BurstLen);
                m_axi_req_o.w.last  = (32'(r_count) == BurstLen - 1);
            end else begin
                m_axi_req_o.w_valid = !r_w_done;
                m_axi_req_o.w.last  = 1'b1;
            end
            if ((r_aw_done || m_axi_rsp_i.aw_ready) &&
                (r_w_done || (m_axi_req_o.w_valid && m_axi_rsp_i.w_ready && m_axi_req_o.w.last))) begin
                w_next_state = S_W_RET;
            end
        end

        S_W_RET: begin
            m_axi_req_o.b_ready = 1'b1;
            if (m_axi_rsp_i.b_valid) w_next_state = S_IDLE;
        end

        S_R_ADDR: begin
            m_axi_req_o.ar_valid = 1'b1;
            w_next_state = m_axi_rsp_i.ar_ready ? S_R_DATA : S_R_ADDR;
        end

        S_R_DATA: begin
            m_axi_req_o.r_ready = 1'b1;
            if (m_axi_rsp_i.r_valid && (!r_burst || m_axi_rsp_i.r.last))
                w_next_state = S_IDLE;
        end

        default: ;
    endcase
end

endmodule
