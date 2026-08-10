VERILATOR ?= verilator
BENDER    ?= bender
BUILD     ?= build

RTL := src/friscv_axi4_full_adapter_intf.sv \
       src/friscv_axi4_full_adapter.sv \
	   src/friscv_from_mem.sv \
	   src/friscv_to_mem.sv \
	   src/mem_to_reg.sv

VFLAGS := --timing --timescale 1ns/1ps -Wall
VLINT_FLAGS := -Wno-SYNCASYNCNET
VSIM_FLAGS := --binary --assert --trace -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET -Wno-DECLFILENAME

sources.f: Bender.yml Bender.lock
	$(BENDER) script flist-plus -t src -t synthesis > $@

ide: .slang/sources.f
.slang/sources.f: Bender.yml Bender.lock .slang/flist.sh
	./.slang/flist.sh > $@

clean:
	rm -rf $(BUILD) sources.f
