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
 * Ports A and B are symmetric, the hub attaches no meaning to either one and
 * rotates priority between them on every completed transaction.
 * The DM port takes priority over both.
 */

module friscv_mem_hub
    import friscv_mem_pkg::*;
#(
    parameter int unsigned ExtBase    = 32'h8000_0000,
    parameter int unsigned ExtSize    = 32'h8000_0000,
    parameter int unsigned CachedBase = ExtBase,
    parameter int unsigned CachedSize = ExtSize,
    parameter int unsigned OcmBase    = 32'h0000_0000,
    parameter int unsigned OcmSize    = 32'h0100_0000,
    parameter int unsigned LineBytes  = 64,
    parameter int unsigned Ways       = 4,
    parameter bit          SramTags   = 1'b1,
    parameter bit          OcmOnly    = 1'b0,
    parameter bit          EnableOcm  = 1'b1
) (
    input  logic            clk_i,
    input  logic            rst_ni,

    // Symmetric port A
    input  friscv_mem_req_t s_a_req_i,
    output friscv_mem_rsp_t s_a_rsp_o,

    // Symmetric port B
    input  friscv_mem_req_t s_b_req_i,
    output friscv_mem_rsp_t s_b_rsp_o,

    // Priority port
    input  friscv_mem_req_t s_dm_req_i,
    output friscv_mem_rsp_t s_dm_rsp_o,

    // To downstream
    output friscv_mem_req_t m_ext_req_o,
    input  friscv_mem_rsp_t m_ext_rsp_i,

    // To the SoC
    output friscv_mem_req_t m_sys_req_o,
    input  friscv_mem_rsp_t m_sys_rsp_i,

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
if (!OcmOnly && EnableOcm &&
    (CachedSize == 0 || CachedSize != 1 << $clog2(CachedSize))) begin : gen_chk_cache_size
    $fatal(1, "CachedSize must be a power of 2, got %0x", CachedSize);
end
if (!OcmOnly && EnableOcm &&
    (CachedBase < ExtBase ||
     (65'(CachedBase) + 65'(CachedSize)) > (65'(ExtBase) + 65'(ExtSize)))
   ) begin : gen_chk_cache_window
    $fatal(1, "the cacheable window (%0x + %0x) must lie inside the external region (%0x + %0x)",
           CachedBase, CachedSize, ExtBase, ExtSize);
end
if (OcmOnly && !EnableOcm) begin : gen_chk_ocm_en_consistent
    $fatal(1, "OcmOnly is set but EnableOcm is not");
end

friscv_mem_req_t granted_req;
friscv_mem_rsp_t granted_rsp;

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

// Frozen copy of a request that has to be held for more than one cycle
friscv_mem_req_t r_a_req, r_b_req, r_dm_req;

// ============================================================
// Issue selection
// ============================================================

logic w_take_a, w_take_b, w_take_dm, w_take_any;

logic w_a_en, w_b_en, w_dm_en;
assign w_a_en  = s_a_req_i.en;
assign w_b_en  = s_b_req_i.en;
assign w_dm_en = s_dm_req_i.en;

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
assign w_done = (r_state != S_IDLE) & ~granted_rsp.stall;

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
        S_HOLD_DM:  if (!granted_rsp.stall) w_next_state = S_IDLE;
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
        r_a_req      <= MEM_REQ_IDLE;
        r_b_req      <= MEM_REQ_IDLE;
        r_dm_req     <= MEM_REQ_IDLE;
    end else begin
        r_state <= w_next_state;

        // Freeze the request if it is going to be held
        if (w_park && w_take_a)  r_a_req  <= s_a_req_i;
        if (w_park && w_take_b)  r_b_req  <= s_b_req_i;
        if (w_park && w_take_dm) r_dm_req <= s_dm_req_i;

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

// Bursts are not supported through the hub, so beat is never raised
always_comb begin
    s_a_rsp_o       = '0;
    s_a_rsp_o.rdata = granted_rsp.rdata;
    s_a_rsp_o.stall = (r_state == S_HOLD_A) ? granted_rsp.stall : 1'b1;
    s_a_rsp_o.err   = (r_state == S_HOLD_A) ? granted_rsp.err   : 1'b0;

    s_b_rsp_o       = '0;
    s_b_rsp_o.rdata = granted_rsp.rdata;
    s_b_rsp_o.stall = (r_state == S_HOLD_B) ? granted_rsp.stall : 1'b1;
    s_b_rsp_o.err   = (r_state == S_HOLD_B) ? granted_rsp.err   : 1'b0;

    s_dm_rsp_o       = '0;
    s_dm_rsp_o.rdata = granted_rsp.rdata;
    s_dm_rsp_o.stall = (r_state == S_HOLD_DM) ? granted_rsp.stall : 1'b1;
    s_dm_rsp_o.err   = (r_state == S_HOLD_DM) ? granted_rsp.err   : 1'b0;
end

always_comb begin
    granted_req = MEM_REQ_IDLE;

    if      (w_busy_dm) granted_req = w_take_dm ? s_dm_req_i : r_dm_req;
    else if (w_busy_a)  granted_req = w_take_a  ? s_a_req_i  : r_a_req;
    else if (w_busy_b)  granted_req = w_take_b  ? s_b_req_i  : r_b_req;

    // Bursts are not supported through the hub
    granted_req.burst = 1'b0;
end

// ============================================================
// Demux to the OCM block, the external memory and the SoC
// ============================================================

friscv_mem_req_t ocm_req;
friscv_mem_rsp_t ocm_rsp;

logic w_match_ext, w_match_ocm;
assign w_match_ext = (granted_req.addr - ExtBase) < ExtSize;
assign w_match_ocm = (granted_req.addr - OcmBase) < OcmSize;

logic w_sel_ocm, w_sel_ext, w_sel_sys;
assign w_sel_ocm = w_match_ocm;
assign w_sel_ext = w_match_ext && !w_match_ocm;
assign w_sel_sys = !w_match_ocm && !w_match_ext;

logic w_sel_blk;
assign w_sel_blk = (!OcmOnly && EnableOcm) ? (w_sel_ocm || w_sel_ext) : w_sel_ocm;

always_comb begin
    ocm_req    = granted_req;
    ocm_req.en = granted_req.en && w_sel_blk;

    m_sys_req_o    = granted_req;
    m_sys_req_o.en = granted_req.en && w_sel_sys;
end

typedef enum logic [1:0] {
    T_SYS,
    T_BLK,
    T_EXT
} target_t;

target_t r_target;
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)         r_target <= T_SYS;
    else if (w_take_any) r_target <= w_sel_blk ? T_BLK : (w_sel_sys ? T_SYS : T_EXT);
end

always_comb begin
    case (r_target)
        T_BLK:   granted_rsp = ocm_rsp;
        T_EXT:   granted_rsp = m_ext_rsp_i;
        T_SYS:   granted_rsp = m_sys_rsp_i;
        default: granted_rsp = m_sys_rsp_i;
    endcase
end

if (!OcmOnly && EnableOcm) begin : gen_ocm_llc

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
        .s_req_i ( ocm_req     ),
        .s_rsp_o ( ocm_rsp     ),
        .m_req_o ( m_ext_req_o ),
        .m_rsp_i ( m_ext_rsp_i )
    );

end else if (EnableOcm) begin : gen_ocm_sram

    localparam int unsigned OcmWords = OcmSize / 4;
    localparam int unsigned OcmAddrW = $clog2(OcmWords);

    if (OcmSize < 4) begin : gen_chk_ocm_size
        $fatal(1, "OcmSize must hold at least one word, got %0x", OcmSize);
    end

    // No cache in this configuration
    assign rd_acc_o  = 1'b0;
    assign rd_miss_o = 1'b0;
    assign wr_acc_o  = 1'b0;

    always_comb begin
        m_ext_req_o    = granted_req;
        m_ext_req_o.en = granted_req.en && w_sel_ext;
    end

    logic        w_req, w_gnt, w_we, w_rvalid;
    logic [31:0] w_addr, w_wdata, w_rdata;
    logic [3:0]  w_be;

    friscv_to_mem #(
        .RegisterReq ( 1 )
    ) to_mem (
        .clk_i,
        .rst_ni,
        .req_o       ( w_req    ),
        .addr_o      ( w_addr   ),
        .we_o        ( w_we     ),
        .wdata_o     ( w_wdata  ),
        .be_o        ( w_be     ),
        .gnt_i       ( w_gnt    ),
        .rvalid_i    ( w_rvalid ),
        .err_i       ( 1'b0     ),
        .other_err_i ( 1'b0     ),
        .rdata_i     ( w_rdata  ),
        .s_req_i     ( ocm_req  ),
        .s_rsp_o     ( ocm_rsp  )
    );

    assign w_gnt = w_req;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) w_rvalid <= 1'b0;
        else         w_rvalid <= w_req && w_gnt;
    end

    tc_sram #(
        .NumWords  ( OcmWords ),
        .DataWidth ( 32       ),
        .ByteWidth ( 8        ),
        .NumPorts  ( 1        ),
        .Latency   ( 1        )
    ) ocm_sram (
        .clk_i,
        .rst_ni,
        .req_i   ( w_req                ),
        .we_i    ( w_we                 ),
        .addr_i  ( w_addr[OcmAddrW+1:2] ),
        .wdata_i ( w_wdata              ),
        .be_i    ( w_be                 ),
        .rdata_o ( w_rdata              )
    );

end else begin : gen_no_ocm

    // No OCM and no cache in this configuration, error on access to OCM
    always_comb begin
        ocm_rsp     = '0;
        ocm_rsp.err = ocm_req.en;
    end

    assign rd_acc_o  = 1'b0;
    assign rd_miss_o = 1'b0;
    assign wr_acc_o  = 1'b0;

    // Pass through the external region
    always_comb begin
        m_ext_req_o    = granted_req;
        m_ext_req_o.en = granted_req.en && w_sel_ext;
    end

end

endmodule
