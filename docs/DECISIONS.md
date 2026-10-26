# Phase 4B decisions

| ID | Decision | Evidence and rationale |
|---|---|---|
| 4B-D1 | Resolve the Yosys GHDL plugin through explicit local paths and provide the GHDL dylib directory in `DYLD_FALLBACK_LIBRARY_PATH` on macOS. | `make synth` invoked `-m ghdl`, but Yosys had no plugin installed in its own plugin directory. The repo's local plugin existed and loaded when addressed by path; `otool -l` showed an obsolete `/tmp` rpath as well as the current `~/tools/ghdl/lib` rpath. Explicit paths make the build reproducible and the environment fallback handles the stale path without modifying system files or the plugin binary. `make synth-check` passed. |
| 4B-D2 | Keep synthesis and implementation measurements local-only; do not put synthesis in `make test` or CI. | Synthesis is toolchain- and platform-dependent and should not extend the fast default regression suite. The dedicated `synth-check` is an explicit local validation target. |

## Phase 4C decisions

| ID | Decision | Evidence and rationale |
|---|---|---|
| 4C-D1 | Keep the BRAM LOAD-stall implementation on `exp-bram`; do not promote it to `main` without a verified default-mode equivalence run and complete comparative results. | The existing experiment changes LOAD timing and MMIO sampling. Its branch report records these semantic changes; the mainline baseline remains the single-cycle design. |
| 4C-D2 | Treat board debug-port cost as an implementation question, not an assumption. | `fpga_top.vhd` already instantiates `cpu_top` with `DEBUG => false` and leaves all `dbg_*` outputs open. A route and netlist inspection are required before attributing board resources or timing to those ports. |
