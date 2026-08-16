# FRISC-V Memory Utilities

This repo contains reusable memory modules and protocol converters for working with the FRISC-V memory protocol (`friscv_mem_req_t` and `friscv_mem_rsp_t`, defined in `friscv_mem_pkg`).

**Included functional modules:**

- `friscv_ocm_llc.sv` - A per-way-configurable On Chip Memory / Last Level Cache.
- `friscv_mem_hub.sv` - A two-port hub (for CPU and DM) splitting the bus between a cached (OCM/LLC) region and uncached System (SoC) region. Setting `OcmOnly` replaces the OCM/LLC with an SRAM block.

**Included protocol converters:**

- FRISC-V -> AXI4 Full (PULP `axi_req_t` / `axi_rsp_t`) - `friscv_to_axi4_full.sv`
- FRISC-V **(no burst)** -> PULP MEM - `friscv_to_mem.sv`
- FRISC-V **(no burst)** -> FER-V SysBus - `friscv_to_sysbus.sv`
- PULP MEM -> FRISC-V **(no burst)** - `mem_to_friscv.sv`
- PULP MEM -> PULP REG - `mem_to_reg.sv`

**Other modules:**

- `friscv_guard.sv` - Enable or error transactions based on an `en` signal.
- `friscv_sysbus_pkg.sv` - Defines default SysBus types.
