# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-08-13

### Added

- `friscv_mem_hub` takes `CachedBase` and `CachedSize`, a cacheable sub-window of the external region.

### Changed

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
