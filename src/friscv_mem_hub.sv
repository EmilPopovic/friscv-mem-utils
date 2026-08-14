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
 * Arbitrates three subordinate ports onto the switchable OCM/LLC block and the
 * system bus, decoding the target from the granted address.
 *
 * s_a_if and s_b_if are symmetric, the hub attaches no meaning to
 * either one and rotates priority between them on every completed transaction.
 * s_dm_if takes priority over both.
 */

module friscv_mem_hub import friscv_mem_pkg::*; #(
    parameter int unsigned ExtBase    = 32'h8000_0000,
    parameter int unsigned ExtSize    = 32'h8000_0000,
    parameter int unsigned CachedBase = ExtBase,
    parameter int unsigned CachedSize = ExtSize,
    parameter int unsigned OcmBase    = 32'h0000_0000,
    parameter int unsigned OcmSize    = 32'h0100_0000,
    parameter int unsigned LineBytes  = 64,
    parameter int unsigned Ways       = 4,
    parameter bit          SramTags   = 1'b1
) (
    input  logic            clk_i,
    input  logic            rst_ni,

    friscv_mem_if.slave     s_a_if,    // Symmetric port A
    friscv_mem_if.slave     s_b_if,    // Symmetric port B
    friscv_mem_if.slave     s_dm_if,   // Priority port
    friscv_mem_if.master    m_ext_if,  // To downstream
    friscv_mem_if.master    m_sys_if,  // To SoC

    input  logic [Ways-1:0] llcsel_i,
    input  logic            crpsel_i,
    input  logic            llcinv_i,

    output logic            rd_acc_o,
    output logic            rd_miss_o,
    output logic            wr_acc_o
);

if (ExtBase % LineBytes != 0) begin : gen_chk_mem_base
    $fatal(1, "ExtBase must be aligned to LineBytes, got %0x", ExtBase);
end
if (OcmBase % LineBytes != 0) begin : gen_chk_sram_base
    $fatal(1, "OcmBase must be aligned to LineBytes, got %0x", OcmBase);
end
if (ExtSize == 0 || ExtSize != 1 << $clog2(ExtSize)) begin : gen_chk_mem_size
    $fatal(1, "ExtSize must be a power of 2, got %0x", ExtSize);
end
if (OcmSize == 0 || OcmSize != 1 << $clog2(OcmSize)) begin : gen_chk_sram_size
    $fatal(1, "OcmSize must be a power of 2, got %0x", OcmSize);
end
if (CachedSize == 0 || CachedSize != 1 << $clog2(CachedSize)) begin : gen_chk_cache_size
    $fatal(1, "CachedSize must be a power of 2, got %0x", CachedSize);
end
if (CachedBase < ExtBase || (65'(CachedBase) + 65'(CachedSize)) > (65'(ExtBase) + 65'(ExtSize))) begin : gen_chk_cache_window
    $fatal(1, "the cacheable window (%0x + %0x) must lie inside the external region (%0x + %0x)", CachedBase, CachedSize, ExtBase, ExtSize);
end

friscv_mem_if granted_if ();

// ============================================================
// Arbitration
// ============================================================

typedef enum logic [1:0] {
    S_IDLE,
    S_HOLD_A,
    S_HOLD_B,
    S_HOLD_DM
} state_t;

state_t r_state, w_next_state;

logic r_b_priority;

addr_t      r_a_addr;
mem_width_e r_a_size;
data_t      r_a_wdata;
rw_cmd_e    r_a_rw;
addr_t      r_b_addr;
mem_width_e r_b_size;
data_t      r_b_wdata;
rw_cmd_e    r_b_rw;
addr_t      r_dm_addr;
mem_width_e r_dm_size;
data_t      r_dm_wdata;
rw_cmd_e    r_dm_rw;

// ============================================================
// Issue selection
// ============================================================

logic w_take_a, w_take_b, w_take_dm, w_take_any;

logic w_a_en, w_b_en, w_dm_en;
assign w_a_en  = s_a_if.rw  != RW_IDLE;
assign w_b_en  = s_b_if.rw  != RW_IDLE;
assign w_dm_en = s_dm_if.rw != RW_IDLE;

always_comb begin
    w_take_a  = 1'b0;
    w_take_b  = 1'b0;
    w_take_dm = 1'b0;
    if (r_state == S_IDLE) begin
        if (w_dm_en) begin
            // DM has priority over A and B
            w_take_dm = 1'b1;
        end else if (w_a_en && w_b_en) begin
            // A and B alternate if both requesting
            w_take_a = !r_b_priority;
            w_take_b =  r_b_priority;
        end else begin
            w_take_a = w_a_en;
            w_take_b = w_b_en;
        end
    end
end

assign w_take_any = w_take_a | w_take_b | w_take_dm;

// A transaction is on the bus this cycle if it is being issued now, or held
logic w_busy_a, w_busy_b, w_busy_dm;
assign w_busy_a  = w_take_a  | (r_state == S_HOLD_A);
assign w_busy_b  = w_take_b  | (r_state == S_HOLD_B);
assign w_busy_dm = w_take_dm | (r_state == S_HOLD_DM);

logic w_park;
assign w_park = w_take_any;

logic w_done;
assign w_done = (r_state != S_IDLE) & ~granted_if.wait_req;

// ============================================================
// Next state
// ============================================================

always_comb begin
    w_next_state = r_state;
    case (r_state)
        S_IDLE:     if (w_park) begin
                        if      (w_take_dm) w_next_state = S_HOLD_DM;
                        else if (w_take_a)  w_next_state = S_HOLD_A;
                        else                w_next_state = S_HOLD_B;
                    end
        S_HOLD_A,
        S_HOLD_B,
        S_HOLD_DM:  if (!granted_if.wait_req) w_next_state = S_IDLE;
        default:    w_next_state = S_IDLE;
    endcase
end

// ============================================================
// Sequential
// ============================================================

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        r_state      <= S_IDLE;
        r_b_priority <= 1'b0;
        r_a_addr     <= '0;
        r_a_size     <= WIDTH_I32;
        r_a_wdata    <= '0;
        r_a_rw       <= RW_IDLE;
        r_b_addr     <= '0;
        r_b_size     <= WIDTH_I32;
        r_b_wdata    <= '0;
        r_b_rw       <= RW_IDLE;
        r_dm_addr    <= '0;
        r_dm_size    <= WIDTH_I32;
        r_dm_wdata   <= '0;
        r_dm_rw      <= RW_IDLE;
    end else begin
        r_state <= w_next_state;

        // Freeze the request if it is going to be held
        if (w_park && w_take_a) begin
            r_a_addr  <= s_a_if.addr;
            r_a_size  <= s_a_if.size;
            r_a_wdata <= s_a_if.wdata;
            r_a_rw    <= s_a_if.rw;
        end
        if (w_park && w_take_b) begin
            r_b_addr  <= s_b_if.addr;
            r_b_size  <= s_b_if.size;
            r_b_wdata <= s_b_if.wdata;
            r_b_rw    <= s_b_if.rw;
        end
        if (w_park && w_take_dm) begin
            r_dm_addr  <= s_dm_if.addr;
            r_dm_size  <= s_dm_if.size;
            r_dm_wdata <= s_dm_if.wdata;
            r_dm_rw    <= s_dm_if.rw;
        end

        // Rotate priority away from whichever of A or B just went
        if (w_done) begin
            if      (w_busy_a) r_b_priority <= 1'b1;
            else if (w_busy_b) r_b_priority <= 1'b0;
        end
    end
end

// ============================================================
// Output
// ============================================================

assign s_a_if.wait_req   = (r_state == S_HOLD_A)   ? granted_if.wait_req : 1'b1;
assign s_b_if.wait_req   = (r_state == S_HOLD_B)   ? granted_if.wait_req : 1'b1;
assign s_dm_if.wait_req  = (r_state == S_HOLD_DM)  ? granted_if.wait_req : 1'b1;
assign s_a_if.err        = (r_state == S_HOLD_A)   ? granted_if.err : 1'b0;
assign s_b_if.err        = (r_state == S_HOLD_B)   ? granted_if.err : 1'b0;
assign s_dm_if.err       = (r_state == S_HOLD_DM)  ? granted_if.err : 1'b0;

always_comb begin
    granted_if.addr  = '0;
    granted_if.size  = WIDTH_I32;
    granted_if.wdata = '0;
    granted_if.rw    = RW_IDLE;

    if (w_busy_dm) begin
        granted_if.addr  = w_take_dm ? s_dm_if.addr  : r_dm_addr;
        granted_if.size  = w_take_dm ? s_dm_if.size  : r_dm_size;
        granted_if.wdata = w_take_dm ? s_dm_if.wdata : r_dm_wdata;
        granted_if.rw    = w_take_dm ? s_dm_if.rw    : r_dm_rw;

    end else if (w_busy_a) begin
        granted_if.addr  = w_take_a ? s_a_if.addr  : r_a_addr;
        granted_if.size  = w_take_a ? s_a_if.size  : r_a_size;
        granted_if.wdata = w_take_a ? s_a_if.wdata : r_a_wdata;
        granted_if.rw    = w_take_a ? s_a_if.rw    : r_a_rw;

    end else if (w_busy_b) begin
        granted_if.addr  = w_take_b ? s_b_if.addr  : r_b_addr;
        granted_if.size  = w_take_b ? s_b_if.size  : r_b_size;
        granted_if.wdata = w_take_b ? s_b_if.wdata : r_b_wdata;
        granted_if.rw    = w_take_b ? s_b_if.rw    : r_b_rw;

    end
end

assign s_a_if.rdata   = granted_if.rdata;
assign s_b_if.rdata   = granted_if.rdata;
assign s_dm_if.rdata  = granted_if.rdata;

// Bursts are not supported through the hub
assign granted_if.burst_en  = 1'b0;
assign s_a_if.beat_valid    = 1'b0;
assign s_b_if.beat_valid    = 1'b0;
assign s_dm_if.beat_valid   = 1'b0;

// ============================================================
// Demux to the OCM/LLC block and the SoC
// ============================================================

friscv_mem_if llc_if ();

logic w_match_ext, w_match_sram;
assign w_match_ext  = (granted_if.addr - addr_t'(ExtBase)) < addr_t'(ExtSize);
assign w_match_sram = (granted_if.addr - addr_t'(OcmBase)) < addr_t'(OcmSize);

logic w_sel_llc, w_sel_sys;
assign w_sel_llc = w_match_ext || w_match_sram;
assign w_sel_sys = !w_sel_llc;

assign llc_if.addr       = granted_if.addr;
assign llc_if.size       = granted_if.size;
assign llc_if.wdata      = granted_if.wdata;
assign llc_if.rw         = w_sel_llc ? granted_if.rw : RW_IDLE;
assign llc_if.burst_en   = 1'b0;

assign m_sys_if.addr     = granted_if.addr;
assign m_sys_if.size     = granted_if.size;
assign m_sys_if.wdata    = granted_if.wdata;
assign m_sys_if.rw       = w_sel_sys ? granted_if.rw : RW_IDLE;
assign m_sys_if.burst_en = 1'b0;

logic r_sel_llc;
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)         r_sel_llc <= 1'b0;
    else if (w_take_any) r_sel_llc <= w_sel_llc;
end

assign granted_if.rdata      = r_sel_llc ? llc_if.rdata      : m_sys_if.rdata;
assign granted_if.wait_req   = r_sel_llc ? llc_if.wait_req   : m_sys_if.wait_req;
assign granted_if.err        = r_sel_llc ? llc_if.err        : m_sys_if.err;
assign granted_if.beat_valid = r_sel_llc ? llc_if.beat_valid : m_sys_if.beat_valid;

// ============================================================
// Switchable OCM/LLC block
// ============================================================

friscv_ocm_llc #(
    .OcmBase      ( OcmBase            ),
    .CachedBase   ( CachedBase         ),
    .CachedLog2   ( $clog2(CachedSize) ),
    .LineBytes    ( LineBytes          ),
    .Ways         ( Ways               ),
    .OcmSizeBytes ( OcmSize            ),
    .SramTags     ( SramTags           )
) ocm_llc (
    .clk_i,
    .rst_ni,
    .crpsel_i,
    .llcinv_i,
    .llcsel_i,
    .rd_acc_o,
    .rd_miss_o,
    .wr_acc_o,
    .s_mem_if ( llc_if   ),
    .m_mem_if ( m_ext_if )
);

endmodule
