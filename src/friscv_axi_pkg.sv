// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>

`include "axi/typedef.svh"

package friscv_axi_pkg;

localparam int unsigned ID_WIDTH   = 1;
localparam int unsigned USER_WIDTH = 1;

typedef logic [31:0]           addr_t;
typedef logic [31:0]           data_t;
typedef logic [3:0]            strb_t;
typedef logic [ID_WIDTH-1:0]   id_t;
typedef logic [USER_WIDTH-1:0] user_t;

`AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)

endpackage
