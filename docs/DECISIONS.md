# Phase 4B decisions

| ID | Decision | Evidence and rationale |
|---|---|---|
| 4B-D1 | Resolve the Yosys GHDL plugin through explicit local paths and provide the GHDL dylib directory in `DYLD_FALLBACK_LIBRARY_PATH` on macOS. | `make synth` invoked `-m ghdl`, but Yosys had no plugin installed in its own plugin directory. The repo's local plugin existed and loaded when addressed by path; `otool -l` showed an obsolete `/tmp` rpath as well as the current `~/tools/ghdl/lib` rpath. Explicit paths make the build reproducible and the environment fallback handles the stale path without modifying system files or the plugin binary. `make synth-check` passed. |
| 4B-D2 | Keep synthesis and implementation measurements local-only; do not put synthesis in `make test` or CI. | Synthesis is toolchain- and platform-dependent and should not extend the fast default regression suite. The dedicated `synth-check` is an explicit local validation target. |
