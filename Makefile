# MiniCPU-8 build/test with NVC and GHDL (VHDL-2008)
#   make test      -- NVC: consistency + Python tests + changed VHDL + all simulations
#   make test-ghdl -- GHDL: analyse and run every testbench (independent simulator)
#   make programs  -- regenerate *_rom.vhd (ROM + RAM packages) from programs/*.asm
#   make fuzz      -- full random differential test (200 programs)
#   make iofuzz    -- full I/O differential test (40 programs)
#   make synth     -- Yosys/GHDL synthesis for HX8K (PROGRAM=hello)
#   make pnr       -- nextpnr place-and-route + bitstream (iCE40HX8K-CT256)
#   make post-synth -- simulate the Yosys/iCE40 netlist (Icarus) vs golden model
#   make waves     -- GHDL VCDs: sum1to10 and hello first UART byte
#   make clean     -- remove both work libraries and generated files
#
# The NVC flow is dependency-aware: one stamp per analysed design unit, with
# explicit source/unit prerequisites.  Only changed units (and their
# dependents) are re-analysed, always in dependency order.

NVC  := nvc
STD  := --std=08
WORK := --work=work
LIB  := work
STAMPS := $(LIB)/.stamps

# GHDL is a second, independent VHDL-2008 simulator.  Override on machines
# where the binary is not on PATH: make GHDL=/path/to/ghdl test-ghdl
GHDL      ?= ghdl
GHDL_DIR  := build/ghdl
GHDL_LOGS := build/ghdl-logs
GHDL_FLAGS := --std=08 --workdir=$(GHDL_DIR)
GHDL_ABS := $(shell command -v $(GHDL) 2>/dev/null || printf '%s' '$(GHDL)')
GHDL_SOURCES = $(PKG_UNITS) $(SRC_UNITS) $(GEN_UNITS) $(TB_UNITS)

# ---- FPGA / synthesis flow ------------------------------------------------
PROGRAM   ?= hello
YOSYS     ?= yosys
GHDL_PLUGIN ?= ghdl
GHDL_PREFIX ?=
NEXTPNR   ?= nextpnr-ice40
DEVICE    ?= hx8k
PACKAGE   ?= ct256
PCF       ?= constraints/hx8k_breakout.pcf
FREQ      ?= 12
SEED      ?= 1

FPGA_BUILD  := build/synth
FPGA_PKG    := $(FPGA_BUILD)/fpga_program.vhd
SYNTH_JSON  := $(FPGA_BUILD)/fpga_top.json
SYNTH_LOG   := $(FPGA_BUILD)/yosys.log
PNR_LOG     := $(FPGA_BUILD)/nextpnr.log
PNR_ASC     := $(FPGA_BUILD)/fpga_top.asc
PNR_BIN     := $(FPGA_BUILD)/fpga_top.bin
FPGA_VHDL   = $(PKG_UNITS:%=%.vhd) $(SRC_UNITS:%=%.vhd) \
               $(PROGRAM)_rom.vhd $(FPGA_PKG) fpga_top.vhd

ifneq ($(GHDL_PREFIX),)
export GHDL_PREFIX
endif

PKG_UNITS := minicpu_pkg
SRC_UNITS := alu register_file flag_reg pc instr_rom data_ram branch_cond \
             control_unit uart_tx gpio cycle_counter mmio cpu_top
TB_UNITS  := uart_rx_model alu_tb register_file_tb flag_reg_tb pc_tb \
             instr_rom_tb data_ram_tb branch_cond_tb alu_compare_tb \
             control_unit_tb uart_tx_tb gpio_tb cycle_counter_tb mmio_tb \
             cpu_tb cpu_edge_tb reset_gating_tb io_cpu_tb \
             uart_demo_tb hello_tb fibonacci_tb primes_tb gpio_demo_tb

PROGS := sum1to10 shift_branch array_sum find_max call_ret \
         unsigned_vs_signed pc_wrap r0_guard \
         hello fibonacci primes gpio_demo
GEN_UNITS := $(addsuffix _rom,$(PROGS))
GEN := $(addsuffix .vhd,$(GEN_UNITS))

RUN := alu_tb register_file_tb flag_reg_tb pc_tb instr_rom_tb data_ram_tb \
       branch_cond_tb alu_compare_tb control_unit_tb uart_tx_tb gpio_tb \
       cycle_counter_tb mmio_tb cpu_tb cpu_edge_tb reset_gating_tb io_cpu_tb \
       hello_tb fibonacci_tb primes_tb gpio_demo_tb

ALL_STAMPS := $(addprefix $(STAMPS)/,$(addsuffix .stamp,$(PKG_UNITS) $(SRC_UNITS) $(GEN_UNITS) $(TB_UNITS)))

.PHONY: all test test-ghdl asmtest simtest consistency programs quickfuzz fuzz ioquickfuzz iofuzz synth pnr post-synth waves clean FORCE

all: test

# ---- Python checks --------------------------------------------------------
asmtest:
	python3 tools/test_assembler.py

simtest:
	python3 tools/test_isa_sim.py

consistency:
	python3 tools/check_consistency.py

# ---- differential fuzzing -------------------------------------------------
quickfuzz:
	python3 tools/fuzz.py --count 20 --seed 20251019 --dir build/fuzz_quick

fuzz:
	python3 tools/fuzz.py --count 200 --seed 20251019 --dir build/fuzz

ioquickfuzz:
	python3 tools/fuzz.py --io --count 8 --seed 20251019 --dir build/iofuzz_quick

iofuzz:
	python3 tools/fuzz.py --io --count 40 --seed 20251019 --dir build/iofuzz

# ---- generated ROM+RAM packages (one file per program) -------------------
%_rom.vhd: programs/%.asm tools/assembler.py
	python3 tools/assembler.py $< --vhdl $@

programs: $(GEN)

# ---- VHDL analysis: incremental, dependency ordered ----------------------
$(LIB)/_NVC_LIB:
	@$(NVC) $(STD) $(WORK) --init
	@mkdir -p $(STAMPS)

define vhdl_rule
$(STAMPS)/$(1).stamp: $(2) | $(LIB)/_NVC_LIB
	@echo "-- a $(1).vhd"
	@$(NVC) $(STD) $(WORK) -a $(1).vhd
	@touch $$@
endef

$(eval $(call vhdl_rule,minicpu_pkg,minicpu_pkg.vhd))
$(eval $(call vhdl_rule,alu,alu.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,register_file,register_file.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,flag_reg,flag_reg.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,pc,pc.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,instr_rom,instr_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,data_ram,data_ram.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,branch_cond,branch_cond.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,control_unit,control_unit.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,uart_tx,uart_tx.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,gpio,gpio.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,cycle_counter,cycle_counter.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,mmio,mmio.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/uart_tx.stamp $(STAMPS)/gpio.stamp $(STAMPS)/cycle_counter.stamp))
$(eval $(call vhdl_rule,cpu_top,cpu_top.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/alu.stamp $(STAMPS)/register_file.stamp $(STAMPS)/flag_reg.stamp $(STAMPS)/pc.stamp $(STAMPS)/instr_rom.stamp $(STAMPS)/data_ram.stamp $(STAMPS)/branch_cond.stamp $(STAMPS)/control_unit.stamp $(STAMPS)/mmio.stamp $(STAMPS)/uart_tx.stamp $(STAMPS)/gpio.stamp $(STAMPS)/cycle_counter.stamp))
$(eval $(call vhdl_rule,sum1to10_rom,sum1to10_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,shift_branch_rom,shift_branch_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,array_sum_rom,array_sum_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,find_max_rom,find_max_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,call_ret_rom,call_ret_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,unsigned_vs_signed_rom,unsigned_vs_signed_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,pc_wrap_rom,pc_wrap_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,r0_guard_rom,r0_guard_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,hello_rom,hello_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,fibonacci_rom,fibonacci_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,primes_rom,primes_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,gpio_demo_rom,gpio_demo_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,alu_tb,alu_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/alu.stamp))
$(eval $(call vhdl_rule,register_file_tb,register_file_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/register_file.stamp))
$(eval $(call vhdl_rule,flag_reg_tb,flag_reg_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/flag_reg.stamp))
$(eval $(call vhdl_rule,pc_tb,pc_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/pc.stamp))
$(eval $(call vhdl_rule,instr_rom_tb,instr_rom_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/instr_rom.stamp))
$(eval $(call vhdl_rule,data_ram_tb,data_ram_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/data_ram.stamp))
$(eval $(call vhdl_rule,branch_cond_tb,branch_cond_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/branch_cond.stamp))
$(eval $(call vhdl_rule,alu_compare_tb,alu_compare_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/alu.stamp $(STAMPS)/branch_cond.stamp))
$(eval $(call vhdl_rule,control_unit_tb,control_unit_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/control_unit.stamp))
$(eval $(call vhdl_rule,uart_rx_model,uart_rx_model.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,uart_tx_tb,uart_tx_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/uart_tx.stamp $(STAMPS)/uart_rx_model.stamp))
$(eval $(call vhdl_rule,gpio_tb,gpio_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/gpio.stamp))
$(eval $(call vhdl_rule,cycle_counter_tb,cycle_counter_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cycle_counter.stamp))
$(eval $(call vhdl_rule,mmio_tb,mmio_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/mmio.stamp $(STAMPS)/uart_rx_model.stamp))
$(eval $(call vhdl_rule,cpu_tb,cpu_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp $(STAMPS)/sum1to10_rom.stamp $(STAMPS)/shift_branch_rom.stamp $(STAMPS)/array_sum_rom.stamp $(STAMPS)/find_max_rom.stamp $(STAMPS)/call_ret_rom.stamp $(STAMPS)/unsigned_vs_signed_rom.stamp $(STAMPS)/pc_wrap_rom.stamp $(STAMPS)/r0_guard_rom.stamp))
$(eval $(call vhdl_rule,cpu_edge_tb,cpu_edge_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp))
$(eval $(call vhdl_rule,reset_gating_tb,reset_gating_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp))
$(eval $(call vhdl_rule,io_cpu_tb,io_cpu_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp $(STAMPS)/uart_rx_model.stamp))
$(eval $(call vhdl_rule,uart_demo_tb,uart_demo_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp $(STAMPS)/uart_rx_model.stamp))
$(eval $(call vhdl_rule,hello_tb,hello_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/uart_demo_tb.stamp $(STAMPS)/hello_rom.stamp))
$(eval $(call vhdl_rule,fibonacci_tb,fibonacci_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/uart_demo_tb.stamp $(STAMPS)/fibonacci_rom.stamp))
$(eval $(call vhdl_rule,primes_tb,primes_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/uart_demo_tb.stamp $(STAMPS)/primes_rom.stamp))
$(eval $(call vhdl_rule,gpio_demo_tb,gpio_demo_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp $(STAMPS)/gpio_demo_rom.stamp))

# ---- run everything ------------------------------------------------------
test: asmtest simtest consistency programs $(ALL_STAMPS)
	@set -e; for tb in $(RUN); do \
	  echo "=== run $$tb ==="; \
	  $(NVC) $(STD) $(WORK) -e $$tb -r; \
	done
	@echo "=== quick differential fuzz (20 ALU/RAM programs) ==="
	@python3 tools/fuzz.py --count 20 --seed 20251019 --dir build/fuzz_quick
	@echo "=== quick I/O differential fuzz (8 programs) ==="
	@python3 tools/fuzz.py --io --count 8 --seed 20251019 --dir build/iofuzz_quick
	@echo "==================================================="
	@echo "ALL TESTBENCHES PASSED"
	@echo "==================================================="

# ---- GHDL: independent simulator, full VHDL-2008 analysis + simulation ---
# Every unit is analysed in dependency order.  Each testbench must both exit
# successfully and print its "ALL TESTS PASSED" banner; a failing testbench
# prints its complete log and aborts make.
test-ghdl: programs
	@set -e; rm -rf $(GHDL_DIR) $(GHDL_LOGS); \
	mkdir -p $(GHDL_DIR) $(GHDL_LOGS); \
	for u in $(GHDL_SOURCES); do \
	  echo "-- ghdl a $$u.vhd"; \
	  $(GHDL) -a $(GHDL_FLAGS) $$u.vhd; \
	done
	@set -e; for tb in $(RUN); do \
	  echo "=== ghdl run $$tb ==="; \
	  ( cd $(GHDL_DIR) && $(GHDL_ABS) --elab-run --std=08 --workdir=. $$tb \
	      --assert-level=error ) > $(GHDL_LOGS)/$$tb.log 2>&1 || { \
	    echo "GHDL FAILED: $$tb"; cat $(GHDL_LOGS)/$$tb.log; exit 1; }; \
	  grep -q "ALL TESTS PASSED" $(GHDL_LOGS)/$$tb.log || { \
	    echo "GHDL: $$tb did not print its PASSED banner"; \
	    cat $(GHDL_LOGS)/$$tb.log; exit 1; }; \
	  grep -E "checks," $(GHDL_LOGS)/$$tb.log | tail -1 || true; \
	done
	@echo "==================================================="
	@echo "ALL GHDL TESTBENCHES PASSED"
	@echo "==================================================="

# ---- FPGA synthesis and place-and-route ----------------------------------
# The generated package keeps the board top synthesizable without run-time
# generic handling: the selected program's ROM/RAM package is referenced
# directly. `make PROGRAM=hello synth`.
$(FPGA_PKG): programs/$(PROGRAM).asm tools/assembler.py FORCE
	@mkdir -p $(FPGA_BUILD)
	@{ \
	  echo "library ieee;"; \
	  echo "use ieee.std_logic_1164.all;"; \
	  echo "use work.minicpu_pkg.all;"; \
	  echo ""; \
	  echo "package fpga_program is"; \
	  echo "  constant PROGRAM : rom_t := work.$(PROGRAM)_rom.PROG;"; \
	  echo "  constant RAM_INIT : ram_init_t := work.$(PROGRAM)_ram.INIT;"; \
	  echo "end package fpga_program;"; \
	} > $@

synth: $(PROGRAM)_rom.vhd $(FPGA_PKG)
	@mkdir -p $(FPGA_BUILD)
	@set -o pipefail; \
	$(YOSYS) -m $(GHDL_PLUGIN) -p \
	  'ghdl --std=08 $(FPGA_VHDL) -e fpga_top; synth_ice40 -top fpga_top -json $(SYNTH_JSON)' \
	  2>&1 | tee $(SYNTH_LOG)
	@echo "SYNTHESIS OK: $(SYNTH_JSON)"

post-synth:
	python3 tools/post_synth.py --programs sum1to10,array_sum,call_ret,hello

# ---- waveform dumps ------------------------------------------------------
GHDL_WAVE_DIR := build/waves/ghdl
WAVE_SOURCES = $(PKG_UNITS) $(SRC_UNITS) $(GEN_UNITS) uart_rx_model \
               sum1to10_wave_tb hello_wave_tb

waves: programs
	@set -e; rm -rf $(GHDL_WAVE_DIR); mkdir -p $(GHDL_WAVE_DIR) docs/waves; \
	for u in $(WAVE_SOURCES); do \
	  $(GHDL) -a --std=08 --workdir=$(GHDL_WAVE_DIR) $$u.vhd; \
	done
	$(GHDL) --elab-run --std=08 --workdir=$(GHDL_WAVE_DIR) \
	  sum1to10_wave_tb --vcd-nodate --vcd=docs/waves/sum1to10.vcd
	$(GHDL) --elab-run --std=08 --workdir=$(GHDL_WAVE_DIR) \
	  hello_wave_tb --vcd-nodate --vcd=docs/waves/hello_first_byte.vcd
	@echo "WAVEFORMS: docs/waves/sum1to10.vcd docs/waves/hello_first_byte.vcd"

pnr: synth
	@set -o pipefail; \
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --json $(SYNTH_JSON) \
	  --pcf $(PCF) --freq $(FREQ) --seed $(SEED) --asc $(PNR_ASC) \
	  --report $(FPGA_BUILD)/nextpnr-report.json 2>&1 | tee $(PNR_LOG)
	icepack $(PNR_ASC) $(PNR_BIN)
	@echo "PNR + BITSTREAM OK: $(PNR_BIN)"

FORCE:

clean:
	rm -rf $(LIB) $(GEN) build
