# MiniCPU-8 build/test with NVC (VHDL-2008)
#   make test    -- assembler tests + compile everything + run ALL testbenches
#   make programs-- regenerate *_rom.vhd from programs/*.asm
#   make clean   -- remove work library and generated files

NVC := nvc
STD := --std=08
WORK := --work=work

PKG   := minicpu_pkg.vhd
SRCS  := alu.vhd register_file.vhd flag_reg.vhd pc.vhd instr_rom.vhd \
         control_unit.vhd cpu_top.vhd
UTBS  := alu_tb.vhd register_file_tb.vhd flag_reg_tb.vhd pc_tb.vhd \
         instr_rom_tb.vhd control_unit_tb.vhd
GEN   := sum1to10_rom.vhd shift_branch_rom.vhd
RUN   := alu_tb register_file_tb flag_reg_tb pc_tb instr_rom_tb \
         control_unit_tb cpu_tb

.PHONY: all test asmtest programs clean

all: test

# ---- assembler ------------------------------------------------------------
asmtest:
	python3 tools/test_assembler.py

# generated ROM packages (one per program, package name = <base>_rom)
%_rom.vhd: programs/%.asm tools/assembler.py
	python3 tools/assembler.py $< --vhdl $@

programs: $(GEN)

# ---- VHDL: analyze in dependency order, then run every testbench ---------
test: asmtest programs
	@for f in $(PKG) $(SRCS) $(GEN) $(UTBS) cpu_tb.vhd; do \
	  echo "-- a $$f"; \
	  $(NVC) $(STD) $(WORK) -a $$f || exit 1; \
	done
	@for tb in $(RUN); do \
	  echo "=== run $$tb ==="; \
	  $(NVC) $(STD) $(WORK) -e $$tb -r || exit 1; \
	done
	@echo "==================================================="
	@echo "ALL TESTBENCHES PASSED"
	@echo "==================================================="

clean:
	rm -rf work $(GEN)
