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
 * This module implements an adapter between the FRISC-V core's memory interface (friscv_mem_if) and a full AXI4 master interface.
 * It supports single-beat and burst transactions of BurstLen beats, which can be configured as needed.
 */

module friscv_to_axi4_full import friscv_mem_pkg::*; #(
    parameter int unsigned BurstLen     = 8,
    parameter int unsigned AxiIdWidth   = 1,
    parameter int unsigned AxiUserWidth = 1,
    localparam int unsigned DataWidth   = DATA_WIDTH
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    friscv_mem_if.slave             s_mem,

    // Write address channel
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,
    output logic [AxiIdWidth-1:0]   m_axi_awid,
    output logic [31:0]             m_axi_awaddr,
    output logic [2:0]              m_axi_awsize,
    output logic [3:0]              m_axi_awcache,
    output logic [2:0]              m_axi_awprot,
    output logic [1:0]              m_axi_awburst,
    output logic [7:0]              m_axi_awlen,
    output logic                    m_axi_awlock,
    output logic [3:0]              m_axi_awqos,
    output logic [3:0]              m_axi_awregion,
    output logic [5:0]              m_axi_awatop,
    output logic [AxiUserWidth-1:0] m_axi_awuser,

    // Write data channel
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,
    output logic                    m_axi_wlast,
    output data_t                   m_axi_wdata,
    output logic [DataWidth/8-1:0]  m_axi_wstrb,
    output logic [AxiUserWidth-1:0] m_axi_wuser,

    // Write response channel
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,
    input  logic [1:0]              m_axi_bresp,

    // Read address channel
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,
    output logic [AxiIdWidth-1:0]   m_axi_arid,
    output logic [31:0]             m_axi_araddr,
    output logic [2:0]              m_axi_arsize,
    output logic [3:0]              m_axi_arcache,
    output logic [2:0]              m_axi_arprot,
    output logic [1:0]              m_axi_arburst,
    output logic [7:0]              m_axi_arlen,
    output logic                    m_axi_arlock,
    output logic [3:0]              m_axi_arqos,
    output logic [3:0]              m_axi_arregion,
    output logic [AxiUserWidth-1:0] m_axi_aruser,

    // Read data channel
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready,
    input  logic                    m_axi_rlast,
    input  data_t                   m_axi_rdata,
    input  logic [1:0]              m_axi_rresp
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
mem_width_e  r_size;
logic        r_burst_en;
logic [31:0] r_addr;
data_t       r_wdata, r_rdata;

logic r_aw_done, r_w_done;

// Count of beats in burst transactions
logic [4:0] r_count;

// Data width and alignment
logic [DATA_WIDTH/8-1:0] base_strb;
logic [$clog2(DATA_WIDTH/8)-1:0] byte_offset;
assign byte_offset = r_addr[$clog2(DATA_WIDTH/8)-1:0];
assign m_axi_wstrb = base_strb << byte_offset;

always_comb begin
    case (r_size)
        WIDTH_I8, WIDTH_U8:   base_strb = 4'b0001;
        WIDTH_I16, WIDTH_U16: base_strb = 4'b0011;
        WIDTH_I32:            base_strb = 4'b1111;
        default:              base_strb = 4'b1111;
    endcase
end

logic [2:0] w_axsize;
always_comb begin
    case (r_size)
        WIDTH_I8, WIDTH_U8:   w_axsize = 3'd0;
        WIDTH_I16, WIDTH_U16: w_axsize = 3'd1;
        WIDTH_I32:            w_axsize = 3'd2;
        default:              w_axsize = 3'd2;
    endcase
end

logic w_read_completing, w_write_completing;
assign w_read_completing  = m_axi_rvalid && m_axi_rready;
assign w_write_completing = m_axi_bvalid && m_axi_bready;

assign m_axi_awid      = '0;
assign m_axi_awaddr    = r_addr;
assign m_axi_awsize    = w_axsize;
assign m_axi_awcache   = 4'b0011;
assign m_axi_awprot    = 3'b000;
assign m_axi_awburst   = 2'b01;
assign m_axi_awlen     = r_burst_en ? (BurstLen - 1) : 8'h00;
assign m_axi_awlock    = 1'b0;
assign m_axi_awqos     = 4'h0;
assign m_axi_awregion  = '0;
assign m_axi_awatop    = '0;
assign m_axi_awuser    = '0;
assign m_axi_wuser     = '0;
assign m_axi_wdata     = r_wdata;

assign m_axi_arid      = '0;
assign m_axi_araddr    = r_addr;
assign m_axi_arsize    = w_axsize;
assign m_axi_arcache   = 4'b0011;
assign m_axi_arprot    = 3'b000;
assign m_axi_arburst   = 2'b01;
assign m_axi_arlen     = r_burst_en ? (BurstLen - 1) : 8'h00;
assign m_axi_arlock    = 1'b0;
assign m_axi_arqos     = 4'h0;
assign m_axi_arregion  = '0;
assign m_axi_aruser    = '0;

assign s_mem.rdata      = w_read_completing ? m_axi_rdata : r_rdata;
assign s_mem.wait_req   = (r_state == S_W_RET)  ? !m_axi_bvalid :
                          (r_state == S_R_DATA) ? !(m_axi_rvalid && (!r_burst_en || m_axi_rlast)) : 1'b1;
assign s_mem.beat_valid = r_burst_en &&
                          (((r_state == S_R_DATA) && m_axi_rvalid && m_axi_rready) ||
                           ((r_state == S_W)      && m_axi_wvalid && m_axi_wready));
assign s_mem.err        = w_read_completing  ? |m_axi_rresp :
                          w_write_completing ? |m_axi_bresp : 1'b0;

// Clocked logic
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        r_burst_en   <= 1'b0;
        r_state      <= S_IDLE;
        r_aw_done    <= 1'b0;
        r_w_done     <= 1'b0;
        r_count      <= '0;
        r_addr       <= '0;
        r_wdata      <= '0;
        r_rdata      <= '0;
        r_size       <= WIDTH_I32;
    end else begin
        r_state <= w_next_state;

        if (r_state == S_IDLE && s_mem.rw != RW_IDLE) begin
            r_addr     <= s_mem.addr;
            r_wdata    <= s_mem.wdata;
            r_size     <= s_mem.size;
            r_burst_en <= s_mem.burst_en;
            r_aw_done  <= 1'b0;
            r_w_done   <= 1'b0;
            r_count    <= '0;
        end

        if (r_state == S_W) begin
            if (m_axi_awvalid && m_axi_awready) r_aw_done <= 1'b1;
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) r_w_done <= 1'b1;

            if (r_burst_en && m_axi_wvalid && m_axi_wready) begin
                r_count <= r_count + 1;
                r_wdata <= s_mem.wdata;
            end
        end

        if (w_read_completing) r_rdata <= m_axi_rdata;
    end
end

always_comb begin
    w_next_state  = r_state;
    m_axi_awvalid = 1'b0;
    m_axi_wvalid  = 1'b0;
    m_axi_wlast   = 1'b0;
    m_axi_bready  = 1'b0;
    m_axi_arvalid = 1'b0;
    m_axi_rready  = 1'b0;

    case (r_state)
        S_IDLE: begin
            if (s_mem.rw == RW_WRITE || s_mem.rw == RW_READ)
                w_next_state = (s_mem.rw == RW_WRITE) ? S_W : S_R_ADDR;
        end

        S_W: begin
            m_axi_awvalid = !r_aw_done;
            if (r_burst_en) begin
                m_axi_wvalid = !r_w_done && (r_count < BurstLen);
                m_axi_wlast  = (r_count == BurstLen - 1);
            end else begin
                m_axi_wvalid = !r_w_done;
                m_axi_wlast  = 1'b1;
            end
            if ((r_aw_done || m_axi_awready) &&
                (r_w_done || (m_axi_wvalid && m_axi_wready && m_axi_wlast))) begin
                w_next_state = S_W_RET;
            end
        end

        S_W_RET: begin
            m_axi_bready = 1'b1;
            if (m_axi_bvalid) w_next_state = S_IDLE;
        end

        S_R_ADDR: begin
            m_axi_arvalid = 1'b1;
            w_next_state  = m_axi_arready ? S_R_DATA : S_R_ADDR;
        end

        S_R_DATA: begin
            m_axi_rready = 1'b1;
            if (m_axi_rvalid && (!r_burst_en || m_axi_rlast))
                w_next_state = S_IDLE;
        end

        default: ;
    endcase
end

endmodule
