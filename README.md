# MiniCPU-8

An educational 8-bit **single-cycle CPU** written in VHDL-2008. Phase 1 scope:
a working core that runs real programs from an instruction ROM and halts.

- 8-bit data path, 8-bit PC (256 instructions), 8 registers (R0 hardwired to 0)
- 16-bit fixed-width instructions, 14 instructions
  (ADD, SUB, AND, OR, NOT, XOR, SHL, SHR, MOV, LOADI, JMP, BEQ, BNE, HALT)
- Z/N/C/V flags; ARM-style carry for SUB (C=1 means no borrow)
- No LOAD/STORE, RAM, CALL/RET, interrupts or pipelining (Phase 2)

Full instruction set and design rationale: [docs/ISA.md](docs/ISA.md).

## Architecture

```
        ┌────────────────────────── cpu_top (single cycle) ─────────────────────┐
        │                                                                       │
  PC ──►│ ROM ─► instr ─► control_unit ─► reg_write / flag_write / alu_src_imm │
        │              │      │                          / alu_op / branch/halt│
        │              │      └──► fields rd/rs/rt ──► register_file ─► rd1 ──►│──► ALU ─► result
        │              └──► imm6 ─► sext ──────────────────────► mux B ─► rd2 ─►│      └► Z N C V
        │                                                                       │        │
        │   comparator(rs==rt) ─► PC logic: +1 / PC+1+imm / target / hold      ◄─┘ flag_reg
        └───────────────────────────────────────────────────────────────────────┘
```

Everything except PC, the register file and the flags is combinational; those
three update on the same rising edge, so one instruction retires per cycle.

## Files

| File | Role |
|---|---|
| `minicpu_pkg.vhd` | shared types, ALU-op enum, opcode constants |
| `alu.vhd` | 8-bit ALU (9 ops incl. PASS_B), Z/N/C/V |
| `register_file.vhd` | 8x8, 2 async read ports, sync write, R0 = 0 |
| `flag_reg.vhd` | Z/N/C/V with write enable |
| `pc.vhd` | reset / increment / load / hold |
| `instr_rom.vhd` | 256-word ROM from generic, HALT-filled above program |
| `control_unit.vhd` | combinational decoder |
| `cpu_top.vhd` | datapath + wiring |
| `*_tb.vhd` | self-checking testbenches (unit + system) |
| `programs/*.asm` | assembly programs |
| `tools/assembler.py` | two-pass assembler (labels, comments, error line numbers) |
| `tools/test_assembler.py` | assembler unit tests |
| `sum1to10_rom.vhd`, `shift_branch_rom.vhd` | **generated** ROM packages |

## Build and test

Requires [NVC](https://www.nickg.me.uk/nvc/) (`brew install nvc`) and Python 3.

```sh
make test      # assembler tests + compile all VHDL + run every testbench
make programs  # regenerate *_rom.vhd from programs/*.asm
make clean     # remove work/ and generated files
```

Everything must end with `ALL TESTBENCHES PASSED`; any testbench failure
aborts `make` with a nonzero exit code (each testbench reports via
`severity failure`).  The VHDL flow is dependency-aware: only sources whose
files or dependencies changed are re-analysed, in dependency order.  Use
`make clean && make test` for the full from-scratch check.

To run one testbench manually:

```sh
nvc --std=08 --work=work -e alu_tb -r
```

## ROM loading, the HALT filler, and PC wrap

The instruction ROM is not initialised from a file at run time. Instead, the
assembler emits a VHDL package containing a `rom_t` constant, and the CPU
receives that constant through the `PROGRAM` generic:

```vhdl
rom_i : entity work.instr_rom
  generic map (INIT => PROGRAM)   -- e.g. work.sum1to10_rom.PROG
  port map (addr => pc_q, data => instr);
```

`instr_rom` copies `INIT` into a 256-word array and fills every remaining word
with **HALT**. Therefore running past the end of a shorter program executes a
HALT and stops the CPU instead of executing uninitialised garbage. (A program
that occupies all 256 words has no filler left; its PC simply wraps to 0.)

The PC is 8 bits, so all PC arithmetic is modulo 256. This is intended:
`PC+1` wraps `0xFF -> 0x00`, a taken relative branch near either end wraps
around, and `JMP 0xFF` executes the last ROM word. `cpu_edge_tb` asserts all of
these cases. See [docs/ISA.md](docs/ISA.md) for the normative statement.

## Assembling and running a program

1. Write `programs/foo.asm`:

   ```asm
   ; count 0..9 in r1
           loadi r1, 0
           loadi r2, 9
   loop:   add   r1, r1, r2
           bne   r2, r0, done   ; demo only: see note
           sub   r2, r2, r1
           jmp   loop
   done:   halt
   ```

2. Generate the ROM package (package name becomes `foo_rom`):

   ```sh
   python3 tools/assembler.py programs/foo.asm --vhdl foo_rom.vhd
   python3 tools/assembler.py programs/foo.asm            # hex words to stdout
   ```

3. Instantiate a CPU with your program in a testbench:

   ```vhdl
   dut : entity work.cpu_top
     generic map (PROGRAM => work.foo_rom.PROG)
     port map (clk => clk, rst => rst, halted => halted,
               dbg_pc => pc, dbg_flags => flags, dbg_regs => regs);
   ```

## Conventions

- `ieee.numeric_std` only; no non-standard Synopsys packages.
- No inferred latches: every combinational process assigns defaults first.
- SUB = `A + not(B) + 1`; C=1 means no borrow (ARM convention).
- Logic ops clear C and V; shifts update C (bit out) and V (sign change, SHL).
- R0 always reads 0; writes ignored. Register file has no reset.

## Test summary

| Testbench | What it covers |
|---|---|
| `alu_tb` | 34 directed + exhaustive ADD/SUB/AND/OR/XOR/NOT/PASS_B (65,536 pairs each) + exhaustive SHL/SHR (256 each) vs an independent reference model |
| `register_file_tb` | dual read, R0 hardwired zero, write-ignore, read-during-write |
| `flag_reg_tb` | reset, hold, load, reset-dominates-enable |
| `pc_tb` | reset, increment, load, hold, wrap 0xFF→0x00 |
| `instr_rom_tb` | INIT readback + HALT fill above the program |
| `control_unit_tb` | full decode table incl. reserved opcodes = NOP |
| `cpu_tb` | system: sum 1..10 = 55 in R1; shifts/XOR/BEQ-taken program; timeouts |
| `cpu_edge_tb` | forward/backward PC wrap, JMP 0xFF, falling into the HALT fill |
| `tools/test_assembler.py` | encodings, labels, ranges, error line numbers |
