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
 * Bridge between a Pulp mem master port and a FRISC-V memory manager port.
 */

module mem_to_friscv import friscv_mem_pkg::*; (
    input  logic            clk_i,
    input  logic            rst_ni,

    input  logic            req_i,
    input  logic [31:0]     addr_i,
    input  logic            we_i,
    input  logic [31:0]     wdata_i,
    input  logic [3:0]      be_i,
    output logic            gnt_o,
    output logic            rvalid_o,
    output logic            err_o,
    output logic            other_err_o,
    output logic [31:0]     rdata_o,

    output friscv_mem_req_t m_req_o,
    input  friscv_mem_rsp_t m_rsp_i
);

typedef enum logic {
    S_IDLE,
    S_BUSY
} state_e;

state_e state_q, state_d;

// Latched transaction fields
logic [31:0] addr_q;
logic [31:0] wdata_q;
logic [3:0]  be_q;
logic        we_q;

// The DM aligns be to the address, so the access width is its population
// count; the byte offset is re-derived from the address downstream.
logic [1:0] size;
always_comb begin
    case (be_q)
        4'b0001, 4'b0010, 4'b0100, 4'b1000: size = SIZE_BYTE;
        4'b0011, 4'b1100:                   size = SIZE_HALF;
        default:                            size = SIZE_WORD;
    endcase
end

// Read data / errors returned to the DM
assign rdata_o     = m_rsp_i.rdata;
assign other_err_o = 1'b0;

always_comb begin
    state_d = state_q;

    gnt_o    = 1'b0;
    rvalid_o = 1'b0;
    err_o    = 1'b0;

    // Constant request fields. en is raised only while the transfer is live.
    m_req_o       = MEM_REQ_IDLE;
    m_req_o.addr  = addr_q;
    m_req_o.size  = size;
    m_req_o.wdata = wdata_q;
    m_req_o.wr    = we_q;

    case (state_q)
        S_IDLE: begin
            gnt_o = req_i;
            if (req_i) state_d = S_BUSY;
        end

        S_BUSY: begin
            m_req_o.en = 1'b1;
            if (!m_rsp_i.stall) begin
                rvalid_o = 1'b1;
                err_o    = m_rsp_i.err;
                state_d  = S_IDLE;
            end
        end

        default: state_d = S_IDLE;
    endcase
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        state_q <= S_IDLE;
        addr_q  <= '0;
        wdata_q <= '0;
        be_q    <= '0;
        we_q    <= 1'b0;
    end else begin
        state_q <= state_d;
        if (state_q == S_IDLE && req_i) begin
            addr_q  <= addr_i;
            wdata_q <= wdata_i;
            be_q    <= be_i;
            we_q    <= we_i;
        end
    end
end

endmodule
