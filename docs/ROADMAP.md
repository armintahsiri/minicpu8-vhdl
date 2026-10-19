# MiniCPU-8 roadmap

This file records what Phase 3 delivered and what remains. The ISA itself is
still defined by `docs/ISA.md`; this is engineering planning, not a second
specification.

## Completed in Phase 3

- **GHDL as a second simulator.** Every testbench runs under GHDL 6.0.0
  (`make test-ghdl`) and the same check counts as NVC. CI has separate NVC and
  GHDL jobs.
- **MMIO + UART.**
  - 240 bytes of data RAM (`0x00..0xEF`), 16 MMIO addresses (`0xF0..0xFF`).
  - 8N1 UART TX with `CLK_FREQ`/`BAUD` generics, busy polling and a documented
    "write while busy is ignored" policy.
  - GPIO_OUT register, two-flop GPIO_IN synchronizer, free-running 8-bit cycle
    counter, deterministic reserved reads.
  - Assembler I/O symbols and rejection of `.data` in the I/O region.
  - Golden-model MMIO/UART timing model and a dedicated I/O differential fuzz
    mode.
- **Demo programs and CPU-level assertions.**
  - `hello.asm` over UART.
  - `fibonacci.asm` with a binary-to-decimal routine and the R7 save
    convention.
  - `primes.asm` with trial division (RAM stays below `0xF0`).
  - `gpio_demo.asm` with a driven GPIO_IN value and checked GPIO_OUT.
- **Synthesizable board top and open-source flow.**
  - `fpga_top.vhd`, generated program package, reset synchronizer.
  - iCE40 HX8K synthesis with GHDL + Yosys, nextpnr place-and-route and a real
    bitstream. Real resource/Fmax numbers are in `docs/SYNTHESIS.md`.
- **Post-synthesis verification.** The Yosys/iCE40 Verilog netlist of
  `sum1to10`, `array_sum`, `call_ret` and `hello` is simulated with Icarus
  Verilog and compared against the golden model (all pass).
- **Waveforms.** `docs/waves/sum1to10.vcd` and
  `docs/waves/hello_first_byte.vcd`.

## Immediate next steps

1. **Hardware bring-up on the iCE40-HX8K Breakout Board.**
   - Verify the PCF (`constraints/hx8k_breakout.pcf`) against the actual board
     revision and 40-pin header.
   - Check LED polarity, reset debounce, UART TX pin/voltage and the actual
     115200 baud error at 12 MHz.
   - Program the bitstream and capture the hello output over a USB-UART
     adapter. None of this was possible in the Phase 3 environment.
2. **A timing-constrained build and sign-off.** Add an SDC-style constraint
   where supported and run static timing at the board clock; the current Fmax
   is a nextpnr estimate only.
3. **CI synthesis smoke test.** A separate job using an oss-cad-suite or
   GHDL/Yosys container could run `make synth` for `hello` and archive the
   reports. This was kept out of the two existing test jobs to keep their run
   time reasonable.

## Larger architectural work

### MiniCPU-16 (recommended next architecture)

The natural successor keeps the educational style but removes the two biggest
limitations of the 8-bit machine:

- 16-bit datapath and 16-bit instructions, with a larger register file.
- A dedicated **stack pointer (SP)** and `PUSH`/`POP`; `CALL`/`RET` use a real
  stack instead of the one-level R7 link.
- 16-bit addressing for code and data, with a defined memory map and room for
  MMIO/UART.
- Keep the ISA regular and document it in the same style: a normative
  `docs/ISA.md`, a Python golden model, assembler, unit tests, differential
  fuzzing and both simulators.
- A single-cycle implementation is still possible at a modest clock; a 3-stage
  pipeline is the next step if higher throughput is the goal.

### RISC-V path

Instead of extending the custom ISA, a small RV32I subset (or a compact
educational subset) would trade the custom ISA for ecosystem familiarity:
assemblers, compilers and debuggers already exist. It is a larger rewrite than
MiniCPU-16 and should not be mixed into the current ISA.

## Ideas deliberately not implemented in Phase 3

- Interrupts, exceptions, a stack pointer, or multi-cycle instructions.
- Pipelining, caches, or a synchronous-memory redesign. These would change the
  single-cycle contract and require new verification.
- A physical-board demo or real hardware timing sign-off.
- Ethernet, SD, video, or other peripherals beyond UART/GPIO/timer.

## Longer-term tooling ideas

- Data labels, `.equ` expressions, macros and a linker for multi-object
  programs.
- A disassembler/debugger front-end for the Python model.
- Formal properties (R0 remains zero, reserved opcodes cannot write) using
  SymbiYosys/GHDL.
- A small monitor/bootloader over UART, and a C compiler or Forth for the
  MiniCPU-16.
- ECP5 target with real LUT-RAM/BRAM trade-off experiments and a second board
  constraint set.
