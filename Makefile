# MiniCPU-8 build/test with NVC (VHDL-2008)
#   make test     -- consistency + assembler/simulator tests + changed VHDL + all simulations
#   make programs -- regenerate *_rom.vhd (ROM + RAM packages) from programs/*.asm
#   make fuzz     -- full random differential test (200 programs)
#   make clean    -- remove the work library and generated files
#
# The VHDL flow is dependency-aware: one stamp per analysed design unit, with
# explicit source/unit prerequisites.  Only changed units (and their
# dependents) are re-analysed, always in dependency order.

NVC  := nvc
STD  := --std=08
WORK := --work=work
LIB  := work
STAMPS := $(LIB)/.stamps

PKG_UNITS := minicpu_pkg
SRC_UNITS := alu register_file flag_reg pc instr_rom data_ram branch_cond \
             control_unit cpu_top
TB_UNITS  := alu_tb register_file_tb flag_reg_tb pc_tb instr_rom_tb \
             data_ram_tb branch_cond_tb alu_compare_tb control_unit_tb \
             cpu_tb cpu_edge_tb reset_gating_tb

PROGS := sum1to10 shift_branch array_sum find_max call_ret \
         unsigned_vs_signed pc_wrap r0_guard
GEN_UNITS := $(addsuffix _rom,$(PROGS))
GEN := $(addsuffix .vhd,$(GEN_UNITS))

RUN := alu_tb register_file_tb flag_reg_tb pc_tb instr_rom_tb data_ram_tb \
       branch_cond_tb alu_compare_tb control_unit_tb cpu_tb cpu_edge_tb \
       reset_gating_tb

ALL_STAMPS := $(addprefix $(STAMPS)/,$(addsuffix .stamp,$(PKG_UNITS) $(SRC_UNITS) $(GEN_UNITS) $(TB_UNITS)))

.PHONY: all test asmtest simtest consistency programs quickfuzz fuzz clean

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
$(eval $(call vhdl_rule,cpu_top,cpu_top.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/alu.stamp $(STAMPS)/register_file.stamp $(STAMPS)/flag_reg.stamp $(STAMPS)/pc.stamp $(STAMPS)/instr_rom.stamp $(STAMPS)/data_ram.stamp $(STAMPS)/branch_cond.stamp $(STAMPS)/control_unit.stamp))
$(eval $(call vhdl_rule,sum1to10_rom,sum1to10_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,shift_branch_rom,shift_branch_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,array_sum_rom,array_sum_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,find_max_rom,find_max_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,call_ret_rom,call_ret_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,unsigned_vs_signed_rom,unsigned_vs_signed_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,pc_wrap_rom,pc_wrap_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,r0_guard_rom,r0_guard_rom.vhd $(STAMPS)/minicpu_pkg.stamp))
$(eval $(call vhdl_rule,alu_tb,alu_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/alu.stamp))
$(eval $(call vhdl_rule,register_file_tb,register_file_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/register_file.stamp))
$(eval $(call vhdl_rule,flag_reg_tb,flag_reg_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/flag_reg.stamp))
$(eval $(call vhdl_rule,pc_tb,pc_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/pc.stamp))
$(eval $(call vhdl_rule,instr_rom_tb,instr_rom_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/instr_rom.stamp))
$(eval $(call vhdl_rule,data_ram_tb,data_ram_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/data_ram.stamp))
$(eval $(call vhdl_rule,branch_cond_tb,branch_cond_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/branch_cond.stamp))
$(eval $(call vhdl_rule,alu_compare_tb,alu_compare_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/alu.stamp $(STAMPS)/branch_cond.stamp))
$(eval $(call vhdl_rule,control_unit_tb,control_unit_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/control_unit.stamp))
$(eval $(call vhdl_rule,cpu_tb,cpu_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp $(STAMPS)/sum1to10_rom.stamp $(STAMPS)/shift_branch_rom.stamp $(STAMPS)/array_sum_rom.stamp $(STAMPS)/find_max_rom.stamp $(STAMPS)/call_ret_rom.stamp $(STAMPS)/unsigned_vs_signed_rom.stamp $(STAMPS)/pc_wrap_rom.stamp $(STAMPS)/r0_guard_rom.stamp))
$(eval $(call vhdl_rule,cpu_edge_tb,cpu_edge_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp))
$(eval $(call vhdl_rule,reset_gating_tb,reset_gating_tb.vhd $(STAMPS)/minicpu_pkg.stamp $(STAMPS)/cpu_top.stamp))

# ---- run everything ------------------------------------------------------
test: asmtest simtest consistency programs $(ALL_STAMPS)
	@set -e; for tb in $(RUN); do \
	  echo "=== run $$tb ==="; \
	  $(NVC) $(STD) $(WORK) -e $$tb -r; \
	done
	@echo "=== quick differential fuzz (20 programs) ==="
	@python3 tools/fuzz.py --count 20 --seed 20251019 --dir build/fuzz_quick
	@echo "==================================================="
	@echo "ALL TESTBENCHES PASSED"
	@echo "==================================================="

clean:
	rm -rf $(LIB) $(GEN) build
