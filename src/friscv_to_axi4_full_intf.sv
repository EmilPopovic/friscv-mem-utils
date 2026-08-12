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
 * PULP AXI_BUS interface adapter for friscv_to_axi4_full.
 */

module friscv_to_axi4_full_intf #(
    parameter int unsigned BurstLen     = 8,
    parameter int unsigned AxiIdWidth   = 1,
    parameter int unsigned AxiUserWidth = 1
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    friscv_mem_if.slave s_mem,
    AXI_BUS.Master      m_axi
);

friscv_to_axi4_full #(
    .BurstLen     ( BurstLen      ),
    .AxiIdWidth   ( AxiIdWidth   ),
    .AxiUserWidth ( AxiUserWidth )
) i_friscv_to_axi4_full (
    .clk_i,
    .rst_ni,
    .s_mem,
    .m_axi_awvalid  ( m_axi.aw_valid  ),
    .m_axi_awready  ( m_axi.aw_ready  ),
    .m_axi_awid     ( m_axi.aw_id     ),
    .m_axi_awaddr   ( m_axi.aw_addr   ),
    .m_axi_awsize   ( m_axi.aw_size   ),
    .m_axi_awcache  ( m_axi.aw_cache  ),
    .m_axi_awprot   ( m_axi.aw_prot   ),
    .m_axi_awburst  ( m_axi.aw_burst  ),
    .m_axi_awlen    ( m_axi.aw_len    ),
    .m_axi_awlock   ( m_axi.aw_lock   ),
    .m_axi_awqos    ( m_axi.aw_qos    ),
    .m_axi_awregion ( m_axi.aw_region ),
    .m_axi_awatop   ( m_axi.aw_atop   ),
    .m_axi_awuser   ( m_axi.aw_user   ),
    .m_axi_wvalid   ( m_axi.w_valid   ),
    .m_axi_wready   ( m_axi.w_ready   ),
    .m_axi_wlast    ( m_axi.w_last    ),
    .m_axi_wdata    ( m_axi.w_data    ),
    .m_axi_wstrb    ( m_axi.w_strb    ),
    .m_axi_wuser    ( m_axi.w_user    ),
    .m_axi_bvalid   ( m_axi.b_valid   ),
    .m_axi_bready   ( m_axi.b_ready   ),
    .m_axi_bresp    ( m_axi.b_resp    ),
    .m_axi_arvalid  ( m_axi.ar_valid  ),
    .m_axi_arready  ( m_axi.ar_ready  ),
    .m_axi_arid     ( m_axi.ar_id     ),
    .m_axi_araddr   ( m_axi.ar_addr   ),
    .m_axi_arsize   ( m_axi.ar_size   ),
    .m_axi_arcache  ( m_axi.ar_cache  ),
    .m_axi_arprot   ( m_axi.ar_prot   ),
    .m_axi_arburst  ( m_axi.ar_burst  ),
    .m_axi_arlen    ( m_axi.ar_len    ),
    .m_axi_arlock   ( m_axi.ar_lock   ),
    .m_axi_arqos    ( m_axi.ar_qos    ),
    .m_axi_arregion ( m_axi.ar_region ),
    .m_axi_aruser   ( m_axi.ar_user   ),
    .m_axi_rvalid   ( m_axi.r_valid   ),
    .m_axi_rready   ( m_axi.r_ready   ),
    .m_axi_rlast    ( m_axi.r_last    ),
    .m_axi_rdata    ( m_axi.r_data    ),
    .m_axi_rresp    ( m_axi.r_resp    )
);

endmodule
