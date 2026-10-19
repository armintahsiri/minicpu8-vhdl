# MiniCPU-8

An educational 8-bit **single-cycle CPU** written in VHDL-2008. Phase 2 adds
immediate arithmetic, data RAM with LOAD/STORE, flag-based comparison and
branches, and CALL/RET, while keeping the one-instruction-per-cycle datapath.
The ISA is specified in [docs/ISA.md](docs/ISA.md), which is the single source
of truth and is mechanically cross-checked against the hardware and assembler.

## Features (ISA v2)

- 8-bit datapath; 8-bit PC (256 instructions, modulo-256 wrap)
- 8 registers `R0..R7`; **R0 hardwired to zero**
- 16-bit fixed-width instructions; all 16 opcodes used
- 256 x 16-bit instruction ROM, loaded through a VHDL generic
- 256 x 8-bit data RAM, asynchronous read / synchronous write, generic init
- Z/N/C/V flags; ARM-style carry for SUB (`C=1` means no borrow)
- ALU: ADD, SUB, AND, OR, NOT, XOR, SHL, SHR, PASS_B
- ADDI; LOAD/STORE; CMP; MOV/NOP/SUBI pseudo-instructions
- BEQ/BNE register-compare branches (Phase 1, unchanged, PC-relative)
- Flag branches: BZ, BNZ, BCS/BHS, BCC/BLO, BN, BNN, BLT, BGE
  (absolute targets; BLT/BGE are exact signed comparisons)
- JMP (absolute); CALL/RET with a single-level link in R7
- HALT freezes the PC; unused ROM is HALT-filled
- No pipelining, interrupts or stack pointer (by design)

## Architecture

```
        ┌───────────────────────────── cpu_top (single cycle) ─────────────────────────────┐
        │                                                                                  │
 PC ───►│ ROM ──► instr ──► control_unit ──► reg_write / mem_read / mem_write / flag_write │
        │          │        │                    / alu_src_imm / rd2_from_rd / wb_sel      │
        │          │        │                    / pc_sel / cond_code / link / halt         │
        │          │        └──► fields rd/rs/rt ──► register_file ──► rd1 ───────────────┐│
        │          │                                  ▲      └──────► rd2 ──► mux ──► rd2 ─┐││
        │          └──► imm6 ─► sext ────────────────┘                 ALU B ▲             │││
        │                                                                     │             │││
        │   ALU (ADD/SUB/logic/shift/PASS_B) ─► result, Z N C V ─► flag_reg   │             │││
        │        │                                                           │             │││
        │        ├─► address = rs + imm (mod 256) ─► data_ram (256x8) ─► rdata│             │││
        │        │                                      ▲ we, dbg             │             │││
        │        └─► writeback mux ◄── ALU / RAM / PC+1 ────────────────────┘             │││
        │                              │                                                   │││
        │                              └─► register_file waddr (R7 when link)              │││
        │                                                                                  │││
        │   eq(rs,rt) ─┐                                                                   │││
        │   branch_cond(flags, cond) ─┴─► PC logic: +1 / absolute / PC+1+imm / R7 / hold ───┘││
        └──────────────────────────────────────────────────────────────────────────────────┘
```

Everything except the PC, register file, flags and data RAM is combinational;
those update on the same rising edge, so one instruction retires per cycle.

## ISA v2 at a glance

| Opcode | Mnemonic | Format | Meaning |
|--------|----------|--------|---------|
| `0x0`-`0x7` | ADD SUB AND OR NOT XOR SHL SHR | R | ALU operations, flags written |
| `0x8` | LOAD | I | `rd <- RAM[rs + sext(imm6)]` |
| `0x9` | LOADI | I | `rd <- sext(imm6)` |
| `0xA`/`0xB` | BEQ/BNE | I | register compare, `PC+1+sext(imm6)` |
| `0xC` | jump group | J | JMP / BZ / BNZ / BCS-BHS / BCC-BLO / BN / BNN / BLT / BGE / CALL |
| `0xD` | STORE | I | `RAM[rs + sext(imm6)] <- rt` (rt in the rd field) |
| `0xE` | ADDI | I | `rd <- rs + sext(imm6)`, flags written |
| `0xF` | EXT | X | NOP, HALT, RET, CMP (function in bits 2:0) |

Pseudo-instructions: `mov rd, rs` = `add rd, rs, r0` (writes flags),
`subi rd, rs, k` = `addi rd, rs, -k`, `nop` = `0xF000`.
Full tables, bit layouts, flag rules and rationale: [docs/ISA.md](docs/ISA.md).

### Data RAM and CALL/RET

- `LOAD rd, [rs+imm]`, `STORE rt, [rs+imm]`; address =
  `(rs + sext(imm6)) mod 256`; offsets -32..+31; 256-byte wrap is intended.
- Bit layouts: LOAD uses rd as destination; STORE puts the **data register in
  the rd field** at bits 11:9 (same trick as BEQ/BNE), base in rs.
- CALL stores `PC+1` in **R7** and jumps to an absolute target. RET jumps to
  R7. There is **no hardware stack**: a nested call must save R7 to RAM and
  restore it before RET (see `programs/call_ret.asm`).

## Files

| File | Role |
|---|---|
| `minicpu_pkg.vhd` | shared types, ALU/writeback/PC enums, opcode/function/condition constants |
| `alu.vhd` | 8-bit ALU (9 ops), Z/N/C/V |
| `branch_cond.vhd` | 4-bit condition decoder (JMP/BZ/BNZ/BCS/BCC/BN/BLT/BGE/CALL) |
| `register_file.vhd` | 8x8, 2 async read ports, sync write, R0 = 0 |
| `flag_reg.vhd` | Z/N/C/V with write enable |
| `pc.vhd` | reset / increment / load / hold |
| `instr_rom.vhd` | 256-word ROM from generic, HALT-filled above the program |
| `data_ram.vhd` | 256x8 RAM, async read, sync write, generic init |
| `control_unit.vhd` | combinational decoder (opcode + function + condition) |
| `cpu_top.vhd` | datapath, RAM, writeback mux, R7 link, PC source mux |
| `*_tb.vhd` | self-checking testbenches (unit + system) |
| `programs/*.asm` | assembly programs (including `.data` arrays) |
| `tools/assembler.py` | two-pass assembler (labels, `.org`, `.data`, errors) |
| `tools/isa_sim.py` | Python golden model (JSON final state) |
| `tools/check_consistency.py` | enforces ISA tables across docs/hardware/assembler |
| `tools/random_programs.py` | random terminating program generator |
| `tools/fuzz.py` | differential fuzz: golden model vs VHDL CPU |
| `*_rom.vhd` | **generated** ROM + RAM packages (one file per program) |

## Build and test

Requires [NVC](https://www.nickg.me.uk/nvc/) (tested with 1.23) and Python 3.

```sh
make test      # consistency + assembler + simulator + all VHDL + quick fuzz (20)
make fuzz      # full differential fuzz (200 random programs)
make programs  # regenerate *_rom.vhd from programs/*.asm
make clean     # remove work/ and generated files
```

`make test` must end with `ALL TESTBENCHES PASSED`; any failure aborts `make`
with a non-zero exit code. The VHDL flow is dependency-aware: one stamp per
analysed unit, with explicit unit/source prerequisites, so only changed units
and their dependents are re-analysed, in dependency order. Use
`make clean && make test` for the full from-scratch check.

To run one testbench manually:

```sh
nvc --std=08 --work=work -e cpu_tb -r
```

## Assembling and running a program

1. Write `programs/foo.asm`:

   ```asm
           .data 16, 1, 2, 3, 4   ; optional RAM initialization
           loadi r1, 16           ; pointer
           loadi r2, 0            ; sum
           loadi r4, 20           ; end pointer
   loop:   load  r3, [r1+0]
           add   r2, r2, r3
           addi  r1, r1, 1
           cmp   r1, r4
           blt   loop             ; signed less-than, absolute target
           store r2, [r0+31]
           halt
   ```

2. Generate the ROM + RAM packages (package names `foo_rom`, `foo_ram`):

   ```sh
   python3 tools/assembler.py programs/foo.asm --vhdl foo_rom.vhd
   python3 tools/assembler.py programs/foo.asm            # hex words to stdout
   python3 tools/isa_sim.py programs/foo.asm              # golden-model run
   ```

3. Instantiate the CPU in a testbench:

   ```vhdl
   dut : entity work.cpu_top
     generic map (PROGRAM  => work.foo_rom.PROG,
                  RAM_INIT => work.foo_ram.INIT)
     port map (clk => clk, rst => rst, halted => halted,
               dbg_pc => pc, dbg_flags => flags, dbg_regs => regs,
               dbg_ram => ram);
   ```

### ROM loading, HALT fill, and PC wrap

The ROM is not loaded from a file at run time. The assembler emits a `rom_t`
constant in a VHDL package; `instr_rom` copies it through the `PROGRAM`
generic and fills every remaining word with **HALT (`0xF001`)**. Running past
the end of a shorter program therefore halts instead of executing garbage.
`.org` gaps inside a program are filled with **NOP (`0xF000`)**.

The PC is 8 bits, so all PC arithmetic is modulo 256: `PC+1` wraps
`0xFF -> 0x00`, a taken relative BEQ/BNE near either end wraps around, and
`JMP 0xFF` executes the last ROM word. A program occupying all 256 words has
no HALT filler, so execution wraps and restarts. `cpu_edge_tb` asserts these
cases; docs/ISA.md §6 is normative.

### Assembly directives

- `.org ADDR` — move the ROM location counter forward (0..255). Gaps become NOP.
- `.data ADDR, V, V, ...` — initialize data RAM (bytes -128..255). It does not
  occupy ROM space. Entry `i` is the byte at address `i`; uncovered addresses
  are zero. Overlapping `.data` writes are an error.
- Labels bind to the next instruction's ROM address. Comments: `;`, `#`, `--`.

## Test summary

| Test / script | What it covers |
|---|---|
| `tools/test_assembler.py` | 104 tests: every encoding (hand-computed), labels, `.org`, `.data`, all error paths |
| `tools/test_isa_sim.py` | 77 tests: ALU/flags, RAM, CMP, conditions, CALL/RET/nesting, wrap, HALT, timeout |
| `tools/check_consistency.py` | 117 checks: pkg ↔ assembler ↔ ISA.md opcode/function/condition tables and layouts |
| `alu_tb` | 459,300 checks: directed + exhaustive ALU vs independent integer reference |
| `alu_compare_tb` | 393,216 checks: all 65,536 `(a,b)` pairs through SUB+branch_cond vs signed/unsigned comparison |
| `branch_cond_tb` | 256 checks: all 16 flag combinations x all 16 condition codes |
| `control_unit_tb` | 2,048 checks: all 16 opcodes x 8 functions x 16 condition codes, every output |
| `data_ram_tb` | 16 checks: init, read/write, write-enable, read-during-write, endpoints |
| `instr_rom_tb` | 8 checks: INIT readback and HALT fill |
| `register_file_tb` | 20 checks: dual read, R0 hardwired, write gating, read-during-write |
| `flag_reg_tb` | 6 checks: reset, hold, load, reset dominates |
| `pc_tb` | 10 checks: reset, increment, load, hold, wrap |
| `cpu_tb` | 70 checks over 8 programs: final regs, flags, PC, RAM, cycle counts |
| `cpu_edge_tb` | 12 checks: forward/backward PC wrap, JMP 0xFF, fall into HALT fill |
| `reset_gating_tb` | 7 checks: reset suppresses register and RAM writes |
| `tools/fuzz.py` | quick 20 / full 200 random programs, golden model vs VHDL, 0 mismatches |

Cycle counts in `cpu_tb` (non-HALT instructions retired; HALT freezes the PC):
`sum1to10=33`, `shift_branch=8`, `array_sum=54`, `find_max=32`, `call_ret=179`,
`unsigned_vs_signed=10`, `pc_wrap=4`, `r0_guard=7`.

## Fuzzing

`tools/random_programs.py` generates reproducible (fixed seed) straight-line
programs with forward-only branches, a CALL to a leaf or nested subroutine,
LOAD/STORE to randomized RAM, and every ALU/immediate operation. `tools/fuzz.py`
assembles each program, runs the golden model, generates a VHDL testbench with
one `cpu_top` per program, runs NVC, parses the dumped final PC/flags/registers/
RAM/cycles, and diffs them. Mismatches print the assembly and both states and
exit non-zero. The quick 20-program run is part of `make test`; `make fuzz`
runs 200. Both also report executed-instruction coverage.

## Conventions

- `ieee.numeric_std` only; no non-standard Synopsys packages.
- No inferred latches: every combinational process assigns defaults first.
- SUB = `A + not(B) + 1`; C=1 means no borrow (ARM convention).
- Logic ops clear C and V; shifts update C (bit out) and V (sign change, SHL).
- R0 always reads 0; writes are ignored for every instruction, including LOAD.
- Reset suppresses register, flag and RAM writes; PC and flags are cleared.
- All 256 ROM words are valid; unused words are HALT.

## Known limitations

- Single-cycle critical path includes ROM + register file + ALU + RAM + control;
  no timing/synthesis constraints are provided.
- No pipelining, interrupts, exceptions, or stack pointer (all by design).
- CALL/RET link is one level in R7; nested calls need explicit save/restore.
- Instruction and data memories are separate 256-word/256-byte spaces.
- LOADI/ADDI immediates are signed 6-bit (-32..+31), so addresses above 31
  need arithmetic or negative offsets (e.g. `[r0-6]` = 0xFA).
- BEQ/BNE keep the Phase 1 PC-relative ±31 range; the new flag branches are
  absolute 8-bit targets.
- `.data` only initializes RAM; there are no data labels, and `.org` may only
  move forward.
- MOV is a pseudo-instruction (`add rd,rs,r0`) and therefore writes flags;
  this differs from the Phase 1 MOV opcode.
- `subi rd, rs, -32` is not encodable (the negated immediate would be +32).
- HALT is detected when the PC points at it; the testbench cycle count excludes
  the HALT instruction itself.
- Verified with NVC 1.23 only; no FPGA synthesis or timing sign-off was run.

## Phase 3 ideas

See [docs/PHASE3_IDEAS.md](docs/PHASE3_IDEAS.md) for UART output, Artix-7
synthesis, interrupts, a stack pointer and other extensions.
