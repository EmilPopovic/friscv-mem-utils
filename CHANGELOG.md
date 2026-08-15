<!-- markdownlint-disable MD024 -->

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [4.0.0] - 2026-08-16

### Added

- Add `friscv_mem_pkg`. `friscv_mem_if` transformed into these struct types.

### Changed

- **Breaking:** No dependency on `friscv-mem-if`, everything uses struct types in `friscv_mem_pkg`.

- **Breaking:** Every `friscv_mem_if` port is now a `friscv_mem_req_t` / `friscv_mem_rsp_t` struct pair.
- **Breaking:** `friscv_to_axi4_full` drives a PULP `axi_req_t` / `axi_rsp_t` struct pair instead of flat signals.

### Removed

- **Breaking:** Remove `friscv_to_axi4_full_intf.sv`. Since the core adapter is not flat, this module is not needed.

## [3.0.0] - 2026-08-14

### Added

- `friscv_mem_hub` takes a third subordinate port. `s_a_if` and `s_b_if` are symmetric.

### Changed

- **Breaking:** `friscv_mem_hub` port `s_cpu_if` is now `s_a_if`, and the new `s_b_if`
  must be connected. An existing integration can move `s_cpu_if` to `s_a_if` and tie
  `s_b_if` off with `rw = RW_IDLE` to keep the previous behaviour.

## [2.0.1] - 2026-08-13

### Fixed

- Fixed elaboration error in `friscv_mem_hub.sv`.

## [2.0.0] - 2026-08-13 [YANKED]

### Added

- `friscv_mem_hub` takes `CachedBase` and `CachedSize`, a cacheable sub-window of the external region.
- `friscv_ocm_llc` and `friscv_mem_hub` expose `rd_acc_o`, `rd_miss_o` and `wr_acc_o`,
  single-cycle pulses for cache statistics. `rd_acc_o` fires on entry to a lookup, so
  the replay lookup after a refill does not double-count; `rd_miss_o` fires once per
  read miss, since that replay always hits. Cacheable writes are always write-through
  and so are counted separately rather than as hits or misses.

### Changed

- [YANKED] because of elaboration error in `friscv_mem_hub.sv`.
- **Breaking:** `friscv_ocm_llc` parameters `ExtBase` and `ExtLog2` are now
  `CachedBase` and `CachedLog2`. They always described the cacheable region rather
  than the external one; the old names only matched because `friscv_mem_hub` passed
  its external region straight through.

## [1.1.0] - 2026-08-13

### Changed

- Renamed repo to `friscv-mem-utils`.

### Added

- Add OCM/LLC module (`friscv_ocm_llc.sv`).
- Add Memory Hub module (`friscv_mem_hub.sv`).

## [1.0.0] - 2026-08-13

### Changed

- Renamed ports and parameters to PULP convention.
- Renamed `friscv_axi4_full_adapter*` to `friscv_to_axi4_full*`.
- Renamed `friscv_from_mem` to `mem_to_friscv`.

### Added

- Added FER-V SysBus support (`friscv_sysbus_pkg.sv`, `friscv_to_sysbus.sv`).

## [0.1.2] - 2026-08-10

### Changed

- All `always_ff` use `@(posedge clk or negedge rstn)`.

## [0.1.1] - 2026-08-10

### Added

- Add `friscv_guard.sv`.

## [0.1.0] - 2026-08-10

### Added

- Initial relase.
