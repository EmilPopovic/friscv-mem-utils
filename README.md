# FRISC-V Adapters

This repo contains bus adapters and other utility modules for working with the FRISC-V memory interface (`friscv_mem_if`).

**Supported conversions:**

- FRISC-V -> AXI4 Full (PULP interface and flat) - `friscv_to_axi4_full_intf.sv`, `friscv_to_axi4_full.sv`
- FRISC-V **(no burst)** -> PULP MEM - `friscv_to_mem.sv`
- FRISC-V **(no burst)** -> FER-V SysBus - `friscv_to_sysbus.sv`
- PULP MEM -> FRISC-V **(no burst)** - `mem_to_friscv.sv`
- PULP MEM -> PULP REG - `mem_to_reg.sv`

**Other modules:**

- `friscv_guard.sv` - Enable or error transactions based on an `en` signal.
- `friscv_sysbus_pkg.sv` - Defines default SysBus types.
