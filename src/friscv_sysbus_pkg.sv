// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>

// Based on FER-V SysBus interface

package friscv_sysbus_pkg;

typedef struct packed {
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0]  we;
    logic        en;
} sys_req_t;

typedef struct packed {
    logic [31:0] rdata;
    logic        rdy;
    logic        err;
} sys_resp_t;

endpackage
