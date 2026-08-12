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
    input  logic         en_i,
    friscv_mem_if.slave  s_mem,
    friscv_mem_if.master m_mem
);

always_comb begin
    // Request path
    m_mem.addr     = s_mem.addr;
    m_mem.size     = s_mem.size;
    m_mem.wdata    = s_mem.wdata;
    m_mem.burst_en = s_mem.burst_en;
    m_mem.rw       = en_i ? s_mem.rw : RW_IDLE;

    // Response path
    if (en_i) begin
        s_mem.rdata      = m_mem.rdata;
        s_mem.wait_req   = m_mem.wait_req;
        s_mem.beat_valid = m_mem.beat_valid;
        s_mem.err        = m_mem.err;
    end else begin
        s_mem.rdata      = '0;
        s_mem.wait_req   = 1'b0;
        s_mem.beat_valid = 1'b0;
        s_mem.err        = (s_mem.rw != RW_IDLE);
    end
end

endmodule
