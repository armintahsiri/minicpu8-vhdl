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
