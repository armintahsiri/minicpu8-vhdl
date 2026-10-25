# EXPERIMENT: synchronous data RAM / iCE40 BRAM

Branch: `exp-bram`. This note is deliberately kept off `main`; no default RTL,
ISA behavior, programs or cycle counts were changed for this experiment.

## Question and current verdict

Can the 256 x 8 data store use iCE40 block RAM and reduce logic enough to fit
UP5K? This experiment is **blocked before synthesis** in the current
environment, so there is no evidence yet that either implementation maps or
fits. `make PROGRAM=hello synth` fails before reading the design because Yosys
0.70 cannot load `ghdl.so` from its configured plugin directory. The plugin is
not installed at the expected path, and network DNS was unavailable during
the audit. Therefore this branch contains an experiment plan and a precise
timing contract, not an unverified RTL implementation.

## A. Asynchronous read / distributed-memory attempt

The baseline `data_ram` has asynchronous read and synchronous write. First
restore the matching `ghdl-yosys-plugin`, then synthesize the unmodified design
and a temporary version with the same 256 x 8 storage replaced by a constant
read stub. Compare FF and LC counts to isolate the storage cost. Inspect the
Yosys iCE40 mapping to determine whether any LUT/distributed-memory resource
is inferred; do not assume iCE40 supports a suitable distributed RAM mapping.
Run HX8K/UP5K PnR before making a fit claim.

The audit's previous phase-3 report says the asynchronous RAM used about 2,000
flip-flops and that UP5K placement failed. Those are historical values, not
measurements from this branch or a fresh stub comparison.

## B. Synchronous BRAM with a stalled LOAD

Keep the default `LOAD_STALL=false` configuration bit-identical. In the
experimental configuration, define LOAD retirement as two clock intervals:

1. During the execute interval, calculate the effective address. At the
   rising edge, issue the BRAM read and save the destination register and
   sequential next PC; do not write the destination yet.
2. During the wait interval, hold the PC and suppress all architectural
   writes and side effects. The BRAM output is now valid.
3. At the following rising edge, write the returned byte to the saved
   destination and advance to the saved next PC. This is the LOAD retirement
   edge. Stores and non-memory instructions retain one-cycle retirement.

Under this contract every LOAD adds exactly one cycle over the default
single-cycle design. Verify register/memory/PC/flag retirement state against
the default model and compare captured UART bytes. Add a golden-model
`load_stall` cycle option that changes cycle timing only; use identical
programs and require identical final architectural state and serial output.
Exercise LOAD at normal RAM and boundary addresses, reset during each LOAD
phase, and ensure a stalled instruction cannot duplicate MMIO writes. MMIO
reads/writes should remain on the existing one-cycle path unless a separate
timing decision explicitly includes them.

## Required completion evidence

- Build a GHDL-Yosys plugin compatible with the local GHDL 6.0.0 and Yosys
  0.70, or use a known compatible toolchain; record exact versions.
- Run A (baseline vs RAM stub) and report FF/LC/BRAM deltas.
- Implement B only behind an opt-in generic/configuration; add default and
  experimental simulator tests and golden-model cycle comparison.
- Run at least seeds 1–5 at 12 MHz on HX8K and UP5K. Report LC/FF/BRAM and
  routed Fmax; include placement failures rather than omitting them.
- Keep all experimental changes on `exp-bram`; do not merge them into `main`
  without an explicit design review.
