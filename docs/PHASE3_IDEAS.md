# MiniCPU-8 — Phase 3 ideas

Phase 2 intentionally stops at a practical but simple single-cycle machine.
These are natural next steps, roughly in increasing order of effort.

## 1. UART / console output

- Add a tiny memory-mapped UART transmitter (e.g. address 0xFFFE/0xFFFF) with
  a `STORE`-only data register and a status bit readable by `LOAD`.
- Add an assembler pseudo-op `putc` (or a macro) and a `print` runtime in
  assembly. A "hello world" program would then be observable without a
  waveform viewer.
- Keep the core single-cycle; the UART can be a separate synchronous block.

## 2. Artix-7 FPGA implementation

- Add a top-level wrapper with a 100 MHz clock, reset button, and LEDs/switches
  for debug; use a clock divider or a slower enable for visible execution.
- Provide XDC constraints and a Vivado project/Makefile target.
- Run synthesis + implementation, report LUT/FF/BRAM usage and the critical
  path. The single-cycle ROM→RF→ALU→RAM→writeback path is the likely limiter;
  consider a 50 MHz constraint first.
- Use block RAM inference for the 256x16 ROM and 256x8 RAM (initialized from
  the generated packages or a `.mem` file).

## 3. Interrupts and a stack pointer

- Add a single interrupt request input, an interrupt-enable flag, and a fixed
  vector (e.g. 0x01). On interrupt: save PC to a link/stack, push flags, jump
  to the vector; `RETI` restores flags and PC.
- Add SP in a register (e.g. R7, or a dedicated 8-bit SP), `PUSH`/`POP`, and
  make CALL/RET use it for unlimited nesting. This removes the Phase 2
  single-level R7 convention and the manual save/restore idiom.
- Keep the cycle count per instruction at one wherever possible; a memory
  push/pop may need an extra cycle or a Harvard stack RAM.

## 4. More instruction-set headroom

- Use the reserved jump conditions (0x9..0xE) and extended functions
  (0x4..0x7) for: MUL (shift-add in hardware or a multi-cycle unit), DIV/MOD,
  signed shifts, byte swap, `SEXT`, `CLZ`, `LDI16`, and a second condition
  group (e.g. carry-set/clear, parity).
- Add `ADDI`-style forms with a 3-bit register + 6-bit immediate already fit
  the I-type; consider a larger immediate via a 2-word instruction if code
  density matters.
- Add a zero-page addressing mode (base R0) and auto-increment/decrement for
  array loops, or a small displacement range larger than ±31.

## 5. Toolchain / verification

- Add data labels and `.equ`/`.align`, expression operands (`label+1`), and
  macros to the assembler.
- Add an ELF/hex loader and a linker script for multi-object programs.
- Formal verification of the decoder/ALU with SymbiYosys (VHDL via GHDL/Yosys)
  or a VHDL equivalence checker; prove R0 remains zero and reserved opcodes
  cannot write.
- Add randomized instruction-level co-simulation with coverage closure and
  mutation testing of the VHDL.
- Add CI (GitHub Actions) that installs NVC and runs `make test`; publish the
  generated ROM/RAM images as artifacts.

## 6. Software

- Write a small C compiler or a Forth interpreter for the ISA.
- Provide library routines: multiply/divide, memset/memcpy, string output,
  and a monitor with load/run/dump commands over UART.
- Add an emulator front-end (the Python model is already close) with a
  disassembler and a simple debugger.

## 7. Performance

- Pipeline fetch/decode/execute (5-stage or 3-stage) with hazard detection and
  forwarding; keep the ISA unchanged.
- Add a branch delay slot or early branch resolution to reduce taken-branch
  cost.
- Add instruction/data caches or separate dual-port RAM for a higher clock.
