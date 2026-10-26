# MiniCPU-8 FPGA bring-up

This guide is a reproducible first-hardware plan. The RTL, constraints and
testbench behavior have been simulated, but no board has been programmed or
measured during this phase. Pin assignments are candidates until confirmed on
the exact board revision.

## Recommended first board

Start with the **Lattice iCE40-HX8K Breakout Board** (HX8K-CT256). Its larger
logic capacity is the best fit for the current CPU, which stores its
asynchronous-read data RAM in flip-flops. The Lattice guide documents the
12 MHz clock, eight user LEDs, FTDI USB interface, SPI flash and 40-pin user
headers. The PCF maps the FTDI receive path to FPGA pin B12 based on the
vendor schematic. The board does not provide the external reset and eight
switch inputs assumed by this wrapper; those need wiring. The B12 route and
all other assignments still need continuity/hardware confirmation.

The iCEBreaker is a convenient alternate for button, serial and PMOD access,
with UP5K-SG48 and published pin mappings. The default asynchronous-RAM design
is not a reliable UP5K fit: only 2/8 place-and-route seeds completed. A separate
`exp-bram` branch experiment uses synchronous RAM reads and a one-cycle LOAD
stall; it fit in one UP5K block RAM and routed on all eight seeds. That branch
changes LOAD timing and peripheral sampling, so HX8K with the default design is
the recommended first hardware target. See [`docs/AUDIT.md`](AUDIT.md) and
[`docs/BRAM_EXPERIMENT.md`](BRAM_EXPERIMENT.md) for the measurements and
behavioral trade-offs.

## Build the image

Install NVC, GHDL 6.0, Yosys with the matching `ghdl-yosys-plugin`,
nextpnr-ice40 and IceStorm. On macOS, the default Makefile paths use the local
GHDL installation under `~/tools`; override `GHDL_PLUGIN` and `GHDL_PREFIX`
when your installation differs. `make synth-check` checks the synthesis
toolchain and builds the hello image.

```sh
make test
make PROGRAM=hello BOARD=hx8k_breakout FREQ=12 SEED=1 bitstream
```

`BOARD=hx8k_breakout` is the default. To try the alternate board:

```sh
make PROGRAM=hello BOARD=icebreaker FREQ=12 SEED=1 bitstream
```

The output is `build/synth/fpga_top.bin`; `PROGRAM` may be `hello`,
`fibonacci`, `primes`, `gpio_demo`, or `hw_selftest`. The build must finish
both synthesis and nextpnr before programming.

## Program and observe

For SRAM programming, connect the board by USB, select its direct-SRAM path
using the board's documented jumper settings, then run:

```sh
iceprog -S build/synth/fpga_top.bin
```

The `-S` option programs volatile SRAM. Flash programming is persistent and
uses a different `iceprog` invocation and jumper configuration; follow the
board guide before changing that configuration. This project has not tested
either programming path on physical hardware.

Open the board's FTDI serial port at **115200 baud, 8 data bits, no parity,
1 stop bit (8N1)**. With the nominal 12 MHz board clock, the integer divider
is 104 clocks, yielding 115,384.615 baud (+0.1603%). On macOS, identify it with
`ls /dev/cu.usb*`, then use
`python3 -m serial.tools.miniterm /dev/cu.usbserial-DEVICE 115200` (install
pyserial if needed). For `hello`, expect exactly:

```text
Hello, MiniCPU-8!
```

Other demo output is listed in the [README](../README.md#demo-programs).
`hw_selftest` increments GPIO_OUT through `0x00..0x0F`, then transmits
`OK\n`, repeating after its polling loop. `gpio_demo` reads GPIO_IN and
outputs the bitwise inverse; drive the eight inputs to `0xA5` to expect
`0x5A` on GPIO_OUT.

### Safe external wiring

- GPIO input and UART signals are **3.3 V logic**. Do not connect an
  RS-232-voltage serial adapter. Use the board FTDI path or a 3.3 V USB-UART
  adapter, connect FPGA TX to adapter RX, and share ground.
- On HX8K, `rst_n` is proposed at K11. Connect a momentary switch from K11 to
  ground and a 10 kΩ pull-up from K11 to 3.3 V. Reset is active low; release
  synchronizes, but there is no debounce circuit.
- HX8K `sw[7:0]` are proposed external inputs at G15, G16, F15, R14, R15,
  H16, R16 and T14. Drive only to ground or 3.3 V and avoid floating inputs.
- iCEBreaker `rst_n` maps to BTN_N (package pin 10); UART TX maps to pin 9.
  Its eight switch inputs use PMOD1A package pins 4, 2, 47, 45, 3, 48, 46,
  and 44. Check the current board revision and docs before attaching signals.
- LED polarity and whether each output is active high have not been measured.

## Troubleshooting

| Symptom | Check |
|---|---|
| No UART bytes | Confirm the image finished loading, 12 MHz clock, reset is released high, 115200 8N1, common ground, and the board's FTDI receive route. On HX8K, verify B12 against the exact schematic/revision. |
| Garbled characters | Confirm 115200 baud and 8N1. The integer divider is 104 clocks, giving 115,384.615 baud (+0.1603%); check the adapter uses 3.3 V TTL. |
| LEDs appear inverted | LED polarity is board-specific and unmeasured. Confirm wiring/polarity before changing RTL. |
| GPIO demo is inconsistent | Ensure every input is driven to a valid 0 V or 3.3 V level. The GPIO synchronizer takes two rising edges to settle. |
| Reset does not restart | Check active-low polarity and pull-up. The HX8K board needs an external reset switch on the candidate K11 pin. |
| Programming fails | Check USB cable, jumper positions and whether SRAM or flash mode is selected; consult the board guide for the board revision. |

## Hardware measurement record

Fill this in after first physical validation; the repository currently has no
hardware observations.

| Measurement | Record |
|---|---|
| Board model and revision | ______________________________ |
| Image / program / commit | ______________________________ |
| Programming path and jumper settings | ______________________________ |
| Clock frequency measured | ______________________________ |
| UART pin continuity and measured baud | ______________________________ |
| UART output bytes / framing errors | ______________________________ |
| LED polarity and output mapping | ______________________________ |
| Reset polarity, restart behavior, debounce | ______________________________ |
| GPIO pin mapping and input levels | ______________________________ |

## References

- [Lattice iCE40-HX8K Breakout Board](https://www.latticesemi.com/products/developmentboardsandkits/ice40hx8kbreakoutboard)
- [Lattice HX8K Breakout Board User Guide](https://www.latticesemi.com/-/media/LatticeSemi/Documents/UserManuals/EI3/FPGA-EB-02031-1-2-iCE40HX-8K-Breakout-Board-User-Guide.ashx?document_id=50373)
- [iCEBreaker hardware documentation](https://docs.icebreaker-fpga.org/hardware/icebreaker/)
- [Official iCEBreaker IceStorm pin constraints](https://github.com/YosysHQ/icestorm/blob/main/examples/icebreaker/icebreaker.pcf)
- [iCEBreaker product listing](https://1bitsquared.com/products/icebreaker) (observed at $79.95 USD on 2026-10-25)
