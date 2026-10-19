# MiniCPU-8 synthesis and timing report (Phase 3)

This report contains **actual tool output** from the open-source flow run in
this repository. It is not a timing sign-off and no physical board was used.

## Target and toolchain

| Item | Value |
|---|---|
| FPGA | Lattice iCE40HX8K-CT256 |
| Board | iCE40-HX8K Breakout Board (12 MHz oscillator) |
| Constraints | `constraints/hx8k_breakout.pcf` (pin assignments **unverified**) |
| Synthesis | GHDL 6.0.0 + ghdl-yosys-plugin `ghdl-v6.0.0` (07a30ed), Yosys 0.70+post |
| Place & route | nextpnr-ice40 0.11.1 (Homebrew build), icestorm 1.1 |
| Netlist simulation | Icarus Verilog 13.0 |
| Host | macOS (Apple silicon) |
| Requested clock | 12 MHz |

The GHDL plugin must be available to Yosys. For a standard install it is
loaded with `-m ghdl`; on this machine it was built at the GHDL 6.0.0 tag and
loaded by path:

```sh
make PROGRAM=hello \
  GHDL_PLUGIN=/path/to/ghdl-yosys-plugin/ghdl.so \
  GHDL_PREFIX=/path/to/ghdl/lib/ghdl \
  FREQ=12 synth

make PROGRAM=hello \
  GHDL_PLUGIN=/path/to/ghdl-yosys-plugin/ghdl.so \
  GHDL_PREFIX=/path/to/ghdl/lib/ghdl \
  FREQ=12 pnr

make post-synth
```

`make synth` generates `build/synth/fpga_program.vhd` from the selected
`PROGRAM` (default `hello`), synthesizes `fpga_top`, and writes
`build/synth/fpga_top.json`. `make pnr` writes the ASC and bitstream:

- `build/synth/fpga_top.asc`
- `build/synth/fpga_top.bin`
- `build/synth/yosys.log`
- `build/synth/nextpnr.log`

## Resource usage (`PROGRAM=hello`)

Yosys statistics after `synth_ice40`:

| Resource | Used |
|---|---:|
| `SB_LUT4` | 2,186 |
| `SB_DFFE` | 1,968 |
| `SB_DFFESR` | 37 |
| `SB_DFFR` | 2 |
| `SB_DFFSR` | 25 |
| **Total flip-flops** | **2,032** |
| `SB_CARRY` | 29 |
| `ICESTORM_RAM` (BRAM) | 0 |
| `ICESTORM_SPRAM` | 0 |

nextpnr-ice40 after packing/placement/routing:

| Resource | Used / available | Utilisation |
|---|---:|---:|
| `ICESTORM_LC` | 4,197 / 7,680 | 54% |
| `ICESTORM_RAM` (4 kbit BRAM) | 0 / 32 | 0% |
| `SB_IO` | 19 / 206 | 9% |
| `SB_GB` | 2 / 8 | 25% |
| `ICESTORM_PLL` | 0 / 2 | 0% |

## Timing (nextpnr, seed 1)

| Metric | Result |
|---|---|
| Requested frequency | 12.00 MHz |
| Fmax after routing | **37.70 MHz** (PASS at 12 MHz) |
| Fmax after placement estimate | 37.99 MHz |
| Critical-path delay | **26.52 ns** (6.62 ns logic + 19.90 ns routing) |
| Routing share of critical path | 75% |

The routed critical path starts at a flag-register bit, crosses the
branch/PC logic and the ROM, then the register file / ALU / data-RAM read mux
and writeback mux, and ends at a register-file flip-flop. The path is
dominated by routing (19.90 ns), not LUT logic. This is expected for a
single-cycle machine where fetch, decode, register read, ALU, data-memory read
and writeback all have to settle in one clock.

`nextpnr` generated a bitstream successfully. The reported Fmax is a static
timing estimate from nextpnr's iCE40 model; it is **not** a hardware
measurement and no board was programmed.

## Why the data RAM becomes flip-flops

GHDL synthesis correctly inferred a 256 x 8 memory for `data_ram` and a
256 x 16 constant ROM for `instr_rom`:

```text
data_ram.vhd:36:10:note: found RAM "mem", width: 8 bits, depth: 256
instr_rom.vhd:31:12:note: found ROM "n202", width: 16 bits, depth: 256
```

The iCE40 mapping in Yosys 0.70 reports:

```text
using FF mapping for memory fpga_top.core.rom_i.:209
using FF mapping for memory fpga_top.core.ram_i.mem
```

The instruction ROM is a constant and is optimised heavily, but the
asynchronous-read data RAM is implemented as ~2,000 flip-flops plus muxing.
iCE40 block RAM has synchronous read; using it would require a pipeline stage
or a stall, which would break the single-cycle contract of this phase. The
iCE40 LUTs in this flow do not provide a usable asynchronous LUT-RAM mapping
for this VHDL style. This is the main reason the smaller iCE40UP5K target was
rejected.

### iCE40UP5K (iCEBreaker) attempt — failed placement

The same netlist was also tried on the iCEBreaker (iCE40UP5K-SG48, 12 MHz):

```text
ICESTORM_LC: 4197/5280 (79%)
ERROR: Unable to find legal placement for cell
'core.ram_i.mem[193]_SB_DFFE_Q_7_DFFLC' of type 'ICESTORM_LC'
```

An earlier run used 4,356 LCs (82%) and also failed placement. The design
therefore does **not** reliably fit/place on the UP5K with this FF-based RAM;
the HX8K target was selected because it has 7,680 LCs.

## What limits the frequency and what would help

1. **Single-cycle memory-to-register path.** The ROM, register file, ALU,
   asynchronous RAM and writeback mux are all in one cycle. A pipeline with a
   synchronous RAM read (and a stall/hazard path for LOAD) is the structural
   fix, but it changes the architecture and was out of scope.
2. **Flip-flop-based data RAM.** ~2,000 FFs plus wide read muxes add both area
   and routing. A BRAM with a one-cycle read latency (pipeline) would reduce
   LCs substantially.
3. **Routing dominates (19.90 of 26.52 ns).** Floorplanning, register
   duplication/retiming, or a larger/faster device (ECP5) would help; the
   next step would be a pipeline and a synchronous memory interface.
4. **No timing constraints beyond the clock.** The design was not signed off
   with STA across corners/temperature; nextpnr's estimate is the only number
   reported here.

## Pin assignments (unverified)

`constraints/hx8k_breakout.pcf` assigns:

- 12 MHz clock: `J3`
- active-low reset: `K11` (external button/header; the board has no on-board
  user button in the referenced pinout)
- UART TX: `H16`
- LEDs: `B5 B4 A2 A1 C5 C4 B3 C3`
- GPIO_IN: `G15 G16 F15 B12 B10 R15 R16 T14` (external DIP/jumper field on
  the 40-pin header)

These pin choices are plausible for an iCE40-HX8K Breakout Board but are
**not verified on hardware**. LED polarity, reset debounce and the exact
header silkscreen must be checked before connecting anything.
