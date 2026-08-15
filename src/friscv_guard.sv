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
 * This module implements a guard for the FRISC-V memory interface.
 * It allows transactions to pass when en_i is high, otherwise it returns an error.
 */

module friscv_guard import friscv_mem_pkg::*; (
    input  logic            en_i,

    input  friscv_mem_req_t s_req_i,
    output friscv_mem_rsp_t s_rsp_o,

    output friscv_mem_req_t m_req_o,
    input  friscv_mem_rsp_t m_rsp_i
);

always_comb begin
    // Request path
    m_req_o    = s_req_i;
    m_req_o.en = en_i && s_req_i.en;

    // Response path
    if (en_i) begin
        s_rsp_o = m_rsp_i;
    end else begin
        s_rsp_o.rdata = '0;
        s_rsp_o.stall = 1'b0;
        s_rsp_o.beat  = 1'b0;
        s_rsp_o.err   = s_req_i.en;
    end
end

endmodule
