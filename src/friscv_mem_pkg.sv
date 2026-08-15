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
 * Types for the FRISC-V memory protocol.
 * A manager drives friscv_mem_req_t and samples friscv_mem_rsp_t, a subordinate does the reverse.
 * A transfer is in flight while en is high and completes on the cycle stall is low.
 */

package friscv_mem_pkg;

    localparam logic [1:0] SIZE_BYTE = 2'b00;
    localparam logic [1:0] SIZE_HALF = 2'b01;
    localparam logic [1:0] SIZE_WORD = 2'b10;

    typedef struct packed {
        logic [31:0] addr;
        logic [1:0]  size;  // 00: byte, 01: halfword, 10: word, 11: reserved
        logic [31:0] wdata;
        logic        en;
        logic        wr;
        logic        burst;
    } friscv_mem_req_t;

    typedef struct packed {
        logic [31:0] rdata;
        logic        stall;
        logic        beat;
        logic        err;
    } friscv_mem_rsp_t;

    // Idle request
    localparam friscv_mem_req_t MEM_REQ_IDLE = '{
        addr:  '0,
        size:  SIZE_WORD,
        wdata: '0,
        en:    1'b0,
        wr:    1'b0,
        burst: 1'b0
    };

endpackage
