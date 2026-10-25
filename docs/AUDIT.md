# MiniCPU-8 Phase 4 audit

Audit started 2026-10-25 in the sole working copy. No RTL or architectural
behavior was changed during this audit. The requested preflight passed: a
temporary file was created and removed, `git status` was clean, and the
configured identity was already `Armin Tahsiri <itsarmintahsiri@gmail.com>`.
The starting commit was `2208fe5`; the repository had no tags.

## Baseline and tool versions

| Command / tool | Result |
|---|---|
| `make clean && make test` | PASS, 8.08 s wall clock; 119 assembler tests, 86 golden-model tests, 152 consistency checks, NVC testbenches and quick differential fuzz (20 normal + 8 I/O) |
| `make fuzz` | PASS, 200 programs, 0 mismatches, 6,974 executed instructions; max 52 cycles; 0.87 s wall clock |
| `make iofuzz` | PASS, 40 programs, 0 mismatches, 8,960 executed instructions; max 224 cycles; 0.52 s wall clock |
| `make GHDL=$HOME/tools/ghdl/bin/ghdl test-ghdl` | PASS, all 22 testbenches; 13.22 s wall clock |
| NVC | 1.23.0, LLVM 23.1.1 (`nvc --version`) |
| GHDL | 6.0.0, LLVM, in `~/tools/ghdl/bin`; not on `PATH` |
| Yosys | 0.70 (`yosys -V`) |
| nextpnr-ice40 | Homebrew formula/bottle 0.11.1_2 (stable upstream 0.11.1); `--version` prints an empty version field on this build. Version obtained from `brew info nextpnr-ice40` / `brew list --versions`, not inferred from that output. |
| icestorm | Homebrew 1.1_1 |
| Icarus Verilog | 13.0 stable |
| Python | 3.12.8 |
| GNU Make | 3.81 |

The phase-3 executable synthesis result is documented in `docs/SYNTHESIS.md`,
but it could not be reproduced in this audit: Yosys failed immediately with
`Can't load module './ghdl'` because its configured `ghdl.so` is absent. A
search under `~/tools/ghdl`, `/tmp`, and the Homebrew paths found no plugin;
shell network access also failed DNS resolution for github.com. Therefore the
requested ten-run seeds 1–5 at 12/50 MHz and temporary RAM-stub synthesis were
not run. Existing phase-3 resource/Fmax values remain historical evidence,
not a Phase 4 rerun.

## ISA, assembler, model, package and RTL consistency

`python3 tools/check_consistency.py` passes all 165 checks after the Phase 4 additions. It checks opcode,
extended function and jump condition values against package constants,
assembler dictionaries and ISA tables; aliases; special words; BEQ/BNE,
STORE/LOAD field-layout examples; RAM size/address-wrap/link conventions; and
the five named MMIO addresses across package, assembler, model and docs. It
also checks selected datapath wiring and the RAM/MMIO decode and write gating.

Gaps not checked by that script: all arithmetic/branch flag equations and
flag-preservation classes; reset values and reset write suppression; the
actual UART divider, frame length and busy boundary; GPIO synchronizer
latency; cycle-counter timing/wrap; every reserved-address and write-access
behavior; generated ROM contents against source beyond assembler unit tests;
and per-opcode end-to-end retirement semantics. The checker also relies on
expected source text snippets, so it is a consistency guard rather than an
independent formal proof. The exhaustive/direct tests below provide some of
these other checks.

The normative document says one instruction retires per cycle, RAM reads are
asynchronous, stores write synchronously, R0 reads as zero and ignores writes,
flags reset to zero and only change for flag-writing operations, reset gates
writes, GPIO input passes through two flops, and UART writes while busy are
dropped. The corresponding package, assembler, golden model, `cpu_top`, and
peripheral implementations were inspected; no ISA encoding or documented
behavior mismatch was found in the audited portions.

## Verification strength and diversity

### Generator diversity (baseline)

For reproducibility, each generated assembly string was SHA-256 hashed. A
second fingerprint normalizes literals, comments and labels to measure program
structure rather than merely different data values.

| Mode | Raw unique / total | Instruction fingerprints unique / total |
|---|---:|---:|
| Normal ALU/RAM, seed 20251019 | 200 / 200 (100%) | 200 / 200 (100%) |
| I/O, seed 20251019 | 40 / 40 (100%) | 40 / 40 (100%) |

The normal generator creates randomized instruction slots and operands. The
I/O generator now emits four structurally distinct polling, back-to-back-write,
interleaved-I/O and randomized-delay patterns. `make test` asserts diversity;
full runs use 200 normal and 40 I/O programs.

### Observed execution coverage

Evidence from the run output and testbench loops:

| Area | Actually exercised |
|---|---|
| Normal quick fuzz (20) | All ALU opcode functions 0–7; ADDI; BEQ/BNE; all used jump conditions 0–8 plus JMP/CALL; CMP; LOAD/STORE; LOADI; NOP; CALL/RET; data RAM only. Output showed 710 instructions. |
| Normal full fuzz (200) | Same required instruction families; 6,974 instructions. All 16 opcodes occur except opcode 0xF extended functions are separately reported as NOP/HALT/CMP/RET; the generator's decoded families include them. RAM accesses are deliberately low-address, not MMIO. |
| I/O quick/full fuzz | LOAD/STORE, LOADI, NOT, CMP and BNZ polling; UART_TX/status, GPIO_OUT/GPIO_IN, cycle counter. Full output after the generator update: 2,786 LOAD, 380 STORE, 2,216 CMP/BNZ, 40 HALT and 50 NOT executions. These tests focus on MMIO behavior rather than full ISA coverage. |
| `alu_tb` | 459,300 checks: exhaustive binary operand pairs for arithmetic/logic/pass operations and all input values for shifts, with Z/N/C/V compared to an integer reference. |
| `alu_compare_tb` | 393,216 checks, including all 65,536 operand pairs through SUB/CMP comparison and conditions. |
| `branch_cond_tb` | 256 combinations: all 16 flag vectors × 16 condition encodings. |
| `control_unit_tb` | 2,048 combinations: 16 opcodes × 8 function values × 16 condition values, checking every control output. |
| RAM/register/PC/reset | Direct tests cover RAM initialization/read/write/read-during-write, R0, PC edge/wrap, and write suppression during reset. No simulator code coverage report is enabled. |
| I/O directed | `mmio_tb`, `io_cpu_tb`, `uart_tx_tb`, `gpio_tb`, `cycle_counter_tb`, and `gpio_demo_tb` exercise listed MMIO paths, busy-drop, polling, synchronizer, and wrap. GPIO tests use a stable driven input and do not test metastability (which RTL simulation cannot model). |

Coverage is execution-count evidence, not a claim of complete RTL coverage.
The golden model accepts a constant GPIO input immediately; its current
I/O-fuzz program reads GPIO only after enough intervening cycles that the
two-flop hardware synchronizer has settled. Dynamic GPIO transitions are
tested at the `gpio` unit, not modeled cycle-by-cycle by I/O fuzz.

### Mutation testing

No MiniCPU-8 mutation tool existed at the start. The sibling MiniCPU-16
`tools/mutation_check.py` was read as a design reference; a separate stdlib
tool was written for this repository. It copies sources to a temporary
directory, changes exactly one RTL line per case, runs `make test`, and stores
`build/mutation-report.json` (ignored build output). All 23 mutations were
detected; there were no survivors:

| Mutation | First detection |
|---|---|
| ADD carry; ADD overflow; SUB carry/no-borrow; logic C flag; SHL carry; SHR carry; SHL result | `alu_tb` |
| LOADI sign extension; PC-relative branch base; RET target | `cpu_tb` |
| R0 write guard | `register_file_tb` |
| MMIO lower-bound decode; UART busy-write gate; GPIO sync stage; reset write gate; RAM write enable | `tools/check_consistency.py` |
| PC reset value | `pc_tb` |
| CMP flag write | `control_unit_tb` |
| CALL link destination | quick differential fuzz only (the only mutation not caught by a directed test or static check) |
| BCS/BCC decode | `branch_cond_tb` |
| UART divider | `uart_tx_tb` |
| UART busy status bit | `mmio_tb` |
| RAM effective-address wrap | `cpu_tb` |
| RAM effective-address wrap | `cpu_tb` |
| RAM effective-address wrap | `cpu_tb` |

The 23 tests ran against temporary copies; no mutation was applied to the
working RTL. CALL-link is a residual directed-test gap, although the quick
differential fuzzer detects it. No test was weakened or deleted.

## Peripheral edge-case audit

| Case | Hand-derived expectation / current evidence | Status |
|---|---|---|
| UART board divider | `floor(12,000,000 / 115,200) = 104`; actual baud `12,000,000 / 104 = 115,384.6153846`; error `(115,384.6153846 / 115,200 - 1) × 100 = +0.1603%`. | `uart_real_divisor_tb` tests the divider under NVC and GHDL. |
| UART frame/busy length | 1 start + 8 LSB-first data + 1 stop = 10 bit periods. | `uart_real_divisor_tb` checks 1,040 cycles at divisor 104. |
| Back-to-back writes | Writes while busy are discarded; a write at the idle boundary is accepted. | Test sends busy `0xAA`, and verifies only `0x55` and `0xA3` arrive. |
| UART status exact edges | Hand-derived: busy asserts on the write edge, stays high through elapsed edge 1039, and clears at elapsed edge 1040. | MMIO status checks all three conditions at divisor 104. |
| GPIO synchronization | Hand-derived: first rising edge captures `pin_in` into `meta`; second rising edge transfers old `meta` to `sync`, so a stable new value is visible after two edges. Unit and MMIO benches assert this. | Tested directly; golden model itself is static/immediate and fuzz does not transition GPIO dynamically. |
| Cycle counter wrap | 8-bit unsigned increment: after `0xFF`, next rising edge yields `0x00`. `cycle_counter_tb` checks 255, wrap and next value 1; MMIO test checks a modulo-256 difference. | Tested. |

No peripheral divergence was observed. The divisor and exact busy-edge cases
pass in both simulators. The golden model still treats GPIO input as static;
dynamic GPIO transitions are covered at the GPIO unit, not by I/O fuzz.

## Assembler/programming ergonomics

The assembler suite passed 119 cases, including malformed register names,
arity, range, undefined/duplicate labels, invalid directives, overlap,
I/O misuse and program overflow. Immediate/address fields are signed six-bit
(-32..31); an arbitrary high-byte address cannot be materialized by one
`loadi`. There is no load-upper/absolute-memory pseudo-op, no stack pointer or
hardware stack, and no multiply/divide. A C-like compiler would need address
materialization, a calling convention/register allocator, stack frames, and
software multiply/divide; a Forth-like implementation would need an explicit
data/return stack in RAM and helpers for literals, indirect memory, arithmetic
and calls. This is a limitation inventory only; no pseudo-instruction was
added during the audit.

## CI audit

At baseline MiniCPU-8 CI used `ubuntu-latest`, NVC `latest`, Ubuntu's moving
GHDL package, and one whole-suite step per job without timeouts, diagnostics
or START/PASS output. That made hangs and version-driven failures hard to
diagnose. Actions cannot be run from this local audit, so CI status is not
claimed.

The sibling MiniCPU-16 workflow was inspected as requested. It pins Ubuntu
24.04, NVC 1.23.0 and GHDL 6.0.0 LLVM; the official GHDL v6.0.0 release page
lists the Ubuntu 24.04 x86-64 LLVM asset SHA-256 as
`e0064cd3d1569e7fca27b186b0d71e80c087de90db4e466ed77dc669a574d8bc`. It also
has bounded steps, runner diagnostics and timeout handling. MiniCPU-16's own
workflow comments report a prior GHDL hang, demonstrating why per-case
timeouts are useful; that is not evidence that MiniCPU-8 CI has failed.
The workflow now pins `ubuntu-24.04`, NVC 1.23.0 and GHDL 6.0.0 LLVM (with the
official asset SHA in the cache key), adds bounded jobs/steps/cases and runner
diagnostics, and emits START/PASS per testbench. Ruby YAML validation passed.
Actions remains unverified until the user pushes.

## Hardware assumptions and board assessment

The default wrapper assumes a 12 MHz clock, an active-low reset button, a
UART-TX pin with compatible voltage/serial adapter, eight ordinary LED
outputs, and eight GPIO inputs. `rst_n` is synchronized for release but has
no debounce filter. PCFs are explicitly marked unverified in the repository.
The HX8K PCF maps clock J3, proposed external reset K11, UART TX B12, LEDs
B5/B4/A2/A1/C5/C4/B3/C3, and external switches G15/G16/F15/R14/R15/H16/R16/T14.
The UART assignment was corrected from H16 using the Lattice schematic
FTDI receive route (PIO0_13/B12); it remains unverified on a physical board.
The Lattice guide documents the 12 MHz oscillator, LEDs, FTDI, headers and
package. The iCEBreaker PCF follows the official YosysHQ IceStorm example and
published board documentation. Both pin files mark assignments unverified.

The iCEBreaker has more suitable first-bring-up conveniences: 12 MHz clock,
FT2232H USB interface exposing programming and a serial port, and published
pinout/docs; however its UP5K resource fit is known to fail in the historic
phase-3 PnR report. The Lattice HX8K breakout has more logic cells (7,680 vs
5,280 per the board docs), eight user LEDs, FTDI, SPI flash, and user headers,
so it is currently the practical CPU target despite requiring more external
reset/switch wiring. As of the inspected product listing, iCEBreaker was
listed at $79.95 USD; no comparable current HX8K sale price was verified.
The build/program commands, safe wiring, expected output, troubleshooting and
measurement checklist are in `docs/BRINGUP.md`.

## Phase 4 verification results

Current diversity is 40/40 in each mode, the checker has 165 checks, 23/23 mutations are detected, and the
divisor-104 MMIO test passes under NVC/GHDL. CALL-link remains fuzz-only.
Synthesis rerun and RAM-stub comparison remain blocked by the absent
GHDL-Yosys plugin and unavailable shell network. Historical phase-3 numbers
must not be presented as a fresh seed sweep.
