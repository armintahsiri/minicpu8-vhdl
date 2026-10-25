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

`python3 tools/check_consistency.py` passed all 152 checks. It checks opcode,
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
second fingerprint removed comments, labels and `.data` directives but kept
the instruction spelling and operands.

| Mode | Raw unique / total | Instruction fingerprints unique / total |
|---|---:|---:|
| Normal ALU/RAM, seed 20251019 | 200 / 200 (100%) | 200 / 200 (100%) |
| I/O, seed 20251019 | 40 / 40 (100%) | 1 / 40 (2.5%) |

The normal generator creates randomized instruction slots and operands. The
I/O generator (`generate_io_one`) emits the same fixed polling/MMIO sequence
for every index; only constants such as bytes and GPIO input vary. Thus raw
hash uniqueness alone would conceal the I/O structural-diversity defect.
`make test` currently runs 20 normal and 8 I/O examples but enforces no hash
uniqueness threshold.

### Observed execution coverage

Evidence from the run output and testbench loops:

| Area | Actually exercised |
|---|---|
| Normal quick fuzz (20) | All ALU opcode functions 0–7; ADDI; BEQ/BNE; all used jump conditions 0–8 plus JMP/CALL; CMP; LOAD/STORE; LOADI; NOP; CALL/RET; data RAM only. Output showed 710 instructions. |
| Normal full fuzz (200) | Same required instruction families; 6,974 instructions. All 16 opcodes occur except opcode 0xF extended functions are separately reported as NOP/HALT/CMP/RET; the generator's decoded families include them. RAM accesses are deliberately low-address, not MMIO. |
| I/O quick/full fuzz | LOAD/STORE, LOADI, NOT, CMP and BNZ polling; UART_TX/status, GPIO_OUT/GPIO_IN, cycle counter. Full output: 2,960 LOAD, 200 STORE, 2,760 CMP/BNZ, 40 HALT and 40 NOT executions. It does not execute the rest of the ISA. The same program structure is repeated. |
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

### Mutation testing status

No MiniCPU-8 mutation tool existed at the start. The sibling MiniCPU-16
`tools/mutation_check.py` uses temporary RTL copies and targeted benches; it
was read as a design reference only and was not copied. The requested
20-mutation experiment (including flags, branches, immediates, R0, RAM wrap,
MMIO/UART/GPIO/reset/PC/shifts/CMP/CALL/RET) remains outstanding at this
audit checkpoint. This is a verification gap; no mutation detection rate is
claimed.

## Peripheral edge-case audit

| Case | Hand-derived expectation / current evidence | Status |
|---|---|---|
| UART board divider | `floor(12,000,000 / 115,200) = 104`; actual baud `12,000,000 / 104 = 115,384.6153846`; error `(115,384.6153846 / 115,200 - 1) × 100 = +0.1603%`. Existing UART benches use divisor 10, not 104. | Arithmetic derived; real-divisor UART frame not yet tested. |
| UART frame/busy length | 1 start + 8 LSB-first data + 1 stop = 10 bit periods. `uart_tx_tb` checks busy duration at divisor 10 and verifies a write while busy is dropped. | Tested at divisor 10; no 104-cycle test. |
| Back-to-back writes | RTL accepts writes only when `uart_busy=0`; writes while busy are discarded. Existing tests intentionally try a second write during the first frame and later write after idle. | Tested at divisor 10, not at 104. |
| UART status exact edges | Busy is asserted on the accepted write edge and drops at the end of bit index 9. The current MMIO bench sees busy and polls until idle but does not assert the exact CPU-visible cycle before/at/after the boundary. | Boundary window missing. |
| GPIO synchronization | Hand-derived: first rising edge captures `pin_in` into `meta`; second rising edge transfers old `meta` to `sync`, so a stable new value is visible after two edges. Unit and MMIO benches assert this. | Tested directly; golden model itself is static/immediate and fuzz does not transition GPIO dynamically. |
| Cycle counter wrap | 8-bit unsigned increment: after `0xFF`, next rising edge yields `0x00`. `cycle_counter_tb` checks 255, wrap and next value 1; MMIO test checks a modulo-256 difference. | Tested. |

No peripheral divergence was observed in the baseline. The exact divisor,
status-edge directed test and dynamic GPIO/model comparison are queued for
the fix stage.

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

MiniCPU-8 CI (`.github/workflows/test.yml`) uses `ubuntu-latest`, installs
NVC `latest`, installs GHDL from Ubuntu's moving apt repository, and runs one
whole-suite step per job. It has no job/step timeout, no diagnostics-on-failure
step, no explicit START/PASS per testbench, and no per-case process timeout.
Thus a simulator or testbench hang can occupy a runner until GitHub's outer
limit; changing runner/tool versions can also introduce non-reproducible
failures. Actions cannot be run from this local audit, so CI status is not
claimed.

The sibling MiniCPU-16 workflow was inspected as requested. It pins Ubuntu
24.04, NVC 1.23.0 and GHDL 6.0.0 LLVM; the official GHDL v6.0.0 release page
lists the Ubuntu 24.04 x86-64 LLVM asset SHA-256 as
`e0064cd3d1569e7fca27b186b0d71e80c087de90db4e466ed77dc669a574d8bc`. It also
has bounded steps, runner diagnostics and timeout handling. MiniCPU-16's own
workflow comments report a prior GHDL hang, demonstrating why per-case
timeouts are useful; that is not evidence that MiniCPU-8 CI has failed.
CI workflow changes and YAML validation remain for the fix stage.

## Hardware assumptions and board assessment

The default wrapper assumes a 12 MHz clock, an active-low reset button, a
UART-TX pin with compatible voltage/serial adapter, eight ordinary LED
outputs, and eight GPIO inputs. `rst_n` is synchronized for release but has
no debounce filter. PCFs are explicitly marked unverified in the repository.
The HX8K PCF maps clock J3, reset K11, UART H16, LEDs B5/B4/A2/A1/C5/C4/B3/C3,
and switches G15/G16/F15/B12/B10/R15/R16/T14. The Lattice HX8K board guide
supports the 12 MHz oscillator, eight LEDs, FTDI USB interface, 40-pin
headers, and chip package, but the current pin choices/reset source and LED
polarity were not checked against an official reference design in this
checkpoint. The iCEBreaker PCF uses SG48 package pin numbers and an alleged
PMOD/LED arrangement; it also has no local board-validation evidence.

The iCEBreaker has more suitable first-bring-up conveniences: 12 MHz clock,
FT2232H USB interface exposing programming and a serial port, and published
pinout/docs; however its UP5K resource fit is known to fail in the historic
phase-3 PnR report. The Lattice HX8K breakout has more logic cells (7,680 vs
5,280 per the board docs), eight user LEDs, FTDI, SPI flash, and user headers,
so it is currently the practical CPU target despite requiring more external
reset/switch wiring. As of the inspected product listing, iCEBreaker was
listed at $79.95 USD; no comparable current HX8K sale price was verified.
This recommendation and cited references will be finalized in
`docs/BRINGUP.md`.

## Audit checkpoint and outstanding work

No ISA/RTL behavior defect was found in the executed baseline. Confirmed
quality gaps are one I/O fuzz structure, absent uniqueness gates, no real
divisor-104 test, no exact status-boundary assertion, CI tool unpinned/no
timeouts, and missing mutations. Synthesis rerun and RAM-stub comparison are
blocked by the absent GHDL-Yosys plugin and unavailable shell network. These
limitations must be resolved or explicitly retained in the final report;
the historical phase-3 numbers must not be presented as a fresh sweep.
