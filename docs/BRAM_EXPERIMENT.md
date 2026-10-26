# EXPERIMENT: synchronous data RAM / iCE40 BRAM

Branch: `exp-bram`. This document and all implementation work here are
experimental and must remain off `main` unless separately reviewed.

## Question and baseline evidence

Can the 256 x 8 data store use iCE40 block RAM and reduce logic enough to fit
UP5K? The baseline asynchronous design synthesizes. Fresh async-read mapping,
seed sweep and disposable RAM-size measurements are recorded in
`docs/AUDIT.md`. GHDL identifies a 256 x 8 RAM, but Yosys maps it to FFs and
LUTs; this flow reports zero `SB_RAM40_4K` and zero `ICESTORM_SPRAM`. It does
not provide a usable async-read distributed RAM mapping for this RTL.

## A. Asynchronous read / distributed memory

The baseline `data_ram` has asynchronous read and synchronous write. Inspect
the Yosys iCE40 mapping and distinguish inference from actual resource use.
The disposable stub/depth comparison in `docs/AUDIT.md` measures scaling. It
is an implementation probe, not an architecturally equivalent CPU.

## B. Synchronous BRAM with LOAD stall

Keep the default `LOAD_STALL=false` configuration bit-identical. In the
experimental configuration, every LOAD, including MMIO reads, retires in two
clock intervals (+1 cycle per LOAD):

1. In the first LOAD interval, address and destination are decoded. At the
   first rising edge, synchronous RAM captures the address and updates its
   output register. The CPU does not write the destination, flags or PC.
   MMIO reads do not access BRAM but use the same wait interval.
2. During the second interval, hold PC at the LOAD and suppress architectural
   writes. Expose the registered RAM byte, or current MMIO read value, to
   writeback.
3. At the second rising edge, write the value to the decoded destination and
   advance PC by one. LOAD retires. Reset in either interval clears the wait
   state and PC, suppresses writes, and restarts at address zero.

STORE and all non-LOAD instructions retain their one-cycle behavior. STORE
does not stall; a following LOAD samples memory after the STORE edge, so no
read-during-write ambiguity is introduced. LOAD does not modify flags. PC
holds for one extra interval and then advances once. No write or UART side
effect is repeated during the wait.

UART status and cycle-counter MMIO reads are sampled at LOAD commit after the
extra interval, so they may differ from the default execution. UART and the
cycle counter continue to advance during the wait. Busy-polling programs can
therefore observe different peripheral timing and total cycles even when
their final registers, RAM, flags, GPIO and accepted UART bytes match. This
change is part of the experiment's behavior and must be reflected in the
golden model.

The golden model gets `load_stall=1`: it advances a cycle before sampling a
LOAD's MMIO read value, then advances another cycle to complete that LOAD.
RAM data is stable during the held interval. Hand-derived tests must first
assert +1 for RAM and MMIO LOADs and no added cycle for STOREs, check PC and
flags at both intervals, and exercise reset in both intervals. Then compare
all program architectural outcomes and UART bytes and require exactly one
additional cycle per executed LOAD.

## Required completion evidence

- Run baseline async RAM and report whether async distributed RAM exists.
- Add the opt-in `LOAD_STALL` generic and sync-read RAM implementation.
- Add hand-derived timing tests, load-stall model tests, all-demo comparisons,
  quick/full differential fuzz under both simulators, and at least five
  mutation spot checks of the new stall logic.
- Synthesize and route seeds 1–8 at 12 and 50 MHz for HX8K and UP5K. Report
  LC, FF, BRAM, Fmax and placement failures, plus demo CPI changes.
- Run the full default configuration regression suite on this branch too.
- Keep all experimental RTL and reports on `exp-bram`; do not merge the
  implementation into `main`.

## Results (2026-10-25)

Yosys inferred one `SB_RAM40_4K`. The synchronous hello design used 395 LC,
139 FF, 279 LUT4, 29 CARRY and one BRAM. Against the default hello build, this
saves 3,802 LC and 1,893 FF. In eight PnR seeds, HX8K routed at 53.09–57.65
MHz (median 56.26), and UP5K routed at 18.92–20.51 MHz (median 19.98). Every
UP5K seed passed the 12 MHz timing constraint and failed a 50 MHz constraint.
Per-seed data and path details are in the EXPERIMENT section of
`docs/AUDIT.md`.

The model's `load_stall` parameter accounts for the extra LOAD interval and
MMIO sampling edge. Hand-derived CPU checks pass under both simulators. The
finite demo set (14 programs) and quick/full ALU/RAM and I/O fuzz sets match
the experimental model under NVC and GHDL; 5/5 targeted stall mutations are
caught. The infinite `hw_selftest` was separately simulated under the option
and emitted `OK\n` while reaching the GPIO pattern. Programs that read the
cycle counter can observe its changed value; `load_stall_demo` does so on
purpose. UART busy polling and cycle totals can therefore change even when
program output is unchanged.

This is synthesis and PnR evidence only. No iCEBreaker or HX8K hardware was
programmed. The current recommendation in `docs/BRINGUP.md` remains the
default configuration on HX8K for first hardware bring-up; the UP5K result is
a promising but behavior-changing experiment, not a merged default.

## Phase 4C complete record

This section records the cycle derivation and comparative sweep directly so
this report is usable without relying on the summary in `AUDIT.md`.

### Exact LOAD and peripheral timing

With `LOAD_STALL=true`, the LOAD spends a first interval with PC held at the
LOAD and architectural write enables suppressed, then commits on the next edge
with PC advanced once. Thus each executed LOAD costs exactly one additional
cycle. LOAD flags are preserved. STORE and all other instructions retain their
one-cycle behavior. The synchronous RAM captures its address on the first LOAD
edge and its registered byte is written to the destination at commit. Reset
while waiting clears the pending state, resets PC and MMIO (including GPIO_OUT,
GPIO synchronizer, cycle counter and UART busy state), and causes execution to
restart at PC 0. A STORE has no duplicate side effect.

| Post-reset cycle | Instruction / phase | PC after edge | R2 | R4 | R7 | RAM[0] | GPIO_OUT | flags |
|---:|---|---:|---:|---:|---:|---:|---:|---|
| 1 | LOADI R1,5 | 01 | 00 | 00 | 00 | 00 | 00 | 0000 |
| 2 | ADDI seeds flags | 02 | 00 | 00 | 00 | 00 | 00 | 0000 |
| 3 | STORE RAM[0] | 03 | 00 | 00 | 00 | 05 | 00 | 0000 |
| 4 | RAM LOAD wait interval | 03 | 00 | 00 | 00 | 05 | 00 | 0000 |
| reset | reset during pending LOAD | 00 | 00 | 00 | 00 | 05 | 00 | 0000 |
| 4 (restart) | RAM LOAD wait interval | 03 | 00 | 00 | 00 | 05 | 00 | 0000 |
| 5 | RAM LOAD commit | 04 | 05 | 00 | 00 | 05 | 00 | 0000 |
| 6 | LOADI GPIO_OUT | 05 | 05 | 00 | 00 | 05 | 00 | 0000 |
| 7 | STORE GPIO_OUT | 06 | 05 | 00 | 00 | 05 | 05 | 0000 |
| 8 | MMIO LOAD wait interval | 06 | 05 | 00 | 00 | 05 | 05 | 0000 |
| 9 | MMIO LOAD commit | 07 | 05 | 05 | 00 | 05 | 05 | 0000 |
| 10 | LOADI CYCLE_COUNT_LO | 08 | 05 | 05 | 00 | 05 | 05 | 0000 |
| 11 | counter LOAD wait interval | 08 | 05 | 05 | 00 | 05 | 05 | 0000 |
| 12 | counter LOAD commit | 09 | 05 | 05 | 0B | 05 | 05 | 0000 |

The table is hand-derived from `programs/load_stall_demo.asm` and matches
`load_stall_tb.vhd` under NVC and GHDL. The cycle-counter LOAD samples at commit,
so it reads `0x0B`; the default asynchronous configuration reads `0x08`. UART
continues advancing during a wait. UART status is sampled at LOAD commit, so a
busy poll may consume more cycles or observe idle one cycle later than in the
default machine. A UART_TX STORE is never stalled; it is accepted only when the
transmitter is idle, and any write during busy remains ignored. Reset clears
UART busy state. No MMIO write is repeated during the wait.

The golden model exposes `load_stall=True` / CLI `--load-stall`; it advances
one peripheral cycle before sampling a LOAD and then completes the LOAD. RAM,
MMIO, flags, reset and UART timing checks all use the same parameter on the
model and CPU simulation. The finite demonstration images matched their
architectural registers, RAM, flags, GPIO and UART bytes, except for programs
that intentionally inspect cycle-counter or UART timing; their changed
cycle-based observations are part of the experiment contract. The fuzz runs
reported in the Results section used the parameter on both sides, under both
NVC and GHDL. Five targeted mutations of stall/commit/PC/MMIO/RAM logic were
caught (5/5).

### Comparative route data

The default asynchronous-RAM netlist used 4,197 LC, 2,032 FF and zero BRAM on
both devices. The experiment used 395 LC, 139 FF and one BRAM on both devices.
Every table cell below is a routed Fmax in MHz; `P` means the requested timing
constraint passed and `F` means routing completed but missed that target. The
UP5K route count is stated as `k of 8 routed`; placement failures are not folded
into a successful-seed median.

| Design / device | Target | seed 1 | seed 2 | seed 3 | seed 4 | seed 5 | seed 6 | seed 7 | seed 8 | Routed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| default HX8K | 12 MHz | 38.46 P | 37.15 P | 38.72 P | 37.42 P | 38.30 P | 36.96 P | 38.37 P | 36.75 P | 8 of 8 |
| LOAD_STALL HX8K | 12 MHz | 56.40 P | 56.12 P | 56.62 P | 57.65 P | 56.42 P | 54.90 P | 55.15 P | 53.09 P | 8 of 8 |
| default UP5K | 12 MHz | place fail | 15.23 P | place fail | place fail | place fail | place fail | place fail | 15.02 P | 2 of 8 |
| LOAD_STALL UP5K | 12 MHz | 20.32 P | 20.51 P | 19.98 P | 19.52 P | 19.77 P | 18.92 P | 19.98 P | 20.51 P | 8 of 8 |
| default HX8K | 50 MHz | 38.46 F | 37.15 F | 38.72 F | 37.42 F | 38.30 F | 36.96 F | 38.37 F | 36.75 F | 8 of 8 |
| LOAD_STALL HX8K | 50 MHz | 56.40 P | 56.12 P | 56.62 P | 57.65 P | 56.42 P | 54.90 P | 55.15 P | 53.09 P | 8 of 8 |
| default UP5K | 50 MHz | place fail | 15.23 F | place fail | place fail | place fail | place fail | place fail | 15.02 F | 2 of 8 |
| LOAD_STALL UP5K | 50 MHz | 20.32 F | 20.51 F | 19.98 F | 19.52 F | 19.77 F | 18.92 F | 19.98 F | 20.51 F | 8 of 8 |

The default UP5K placement failures are seeds 1, 3, 4, 5, 6 and 7. The LOAD_STALL
experiment routes all eight UP5K seeds at 12 MHz, with routed Fmax 18.92–20.51
MHz; at a 50 MHz target all eight routes complete but fail timing. Targeting
12 versus 50 MHz did not change the achieved Fmax values in the recorded
sweeps. These are synthesis/PnR results, not timing sign-off or board evidence.

### Demo CPI and verdict

| Program | Default cycles / CPI | LOAD_STALL cycles / CPI | Output / other observation |
|---|---:|---:|---|
| array_sum | 54 / 1.000 | 64 / 1.185 | same architectural result |
| call_ret | 179 / 1.000 | 180 / 1.006 | same architectural result |
| find_max | 32 / 1.000 | 37 / 1.156 | same architectural result |
| gpio_demo | 6 / 1.000 | 8 / 1.333 | GPIO_IN=00 gives GPIO_OUT=FF in both |
| hello | 18,817 / 1.000 | 18,822 / 1.333 | 18 bytes identical |
| fibonacci | 39,729 / 1.000 | 39,745 / 1.329 | 38 bytes identical |
| primes | 408,065 / 1.000 | 427,552 / 1.151 | 188 bytes identical |
| ram_wrap | 4 / 1.000 | 5 / 1.250 | same architectural result |
| load_stall_demo | 9 / 1.000 | 12 / 1.333 | cycle-counter value 08 -> 0B by design |

Decision: keep LOAD_STALL on `exp-bram`. Its smaller resource footprint and
8/8 UP5K placement are compelling implementation evidence, but the additional
cycle per LOAD changes CPI and MMIO observation time, particularly for UART
busy polling and cycle-counter reads. It is not promoted to `main`; the default
single-cycle behavior remains the production contract. No board was programmed.
