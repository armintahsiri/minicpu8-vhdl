# MiniCPU-8 Instruction Set Architecture (v2)

MiniCPU-8 is an educational 8-bit **single-cycle** CPU. It executes exactly one
instruction per clock cycle. This document is the normative ISA specification:
`minicpu_pkg.vhd`, `tools/assembler.py`, `tools/isa_sim.py`, the testbenches and
this file are kept in sync by `tools/check_consistency.py`.

- **Data path:** 8 bits
- **Program Counter:** 8 bits, modulo 256
- **Registers:** 8 x 8-bit `R0..R7`; **R0 is hardwired to zero** (reads 0, writes ignored)
- **Instruction memory:** 256 x 16-bit ROM, loaded through a VHDL generic
- **Data memory:** 256 x 8-bit RAM (Harvard: separate from the instruction ROM)
- **Link register:** R7 (one level, no hardware stack)
- **Execution:** one instruction per clock; no pipelining, interrupts or stack pointer

## 1. Instruction formats

All instructions are 16 bits wide.

```
R-type : [ op:4 | rd:3 | rs:3 | rt:3 | 000:3 ]
I-type : [ op:4 | rd:3 | rs:3 | imm6:6      ]
J-type : [ op:4 | cond:4      | target:8    ]
X-type : [ 1111 | rd:3 | rs:3 | rt:3 | func:3 ]   (extended group, opcode 0xF)
         15  12 11  9 8   6 5   3 2   0
```

- `rd` (bits 11:9): destination register for ALU/LOAD/LOADI/ADDI, the **data
  source register for STORE**, and the **second compared register for BEQ/BNE**.
- `rs` (bits 8:6): first source register / memory base register.
- `rt` (bits 5:3): second source register in R-type and CMP.
- `imm6` (bits 5:0): 6-bit immediate, sign-extended to 8 bits.
- `cond` (bits 11:8): jump-group condition/operation code (absolute target).
- `target` (bits 7:0): absolute instruction address 0..255.
- `func` (bits 2:0): extended-group function code.
- Bits documented as zero are ignored by hardware and emitted as zero by the
  assembler.

### Normative field layouts

```
R-type (ALU)       : op[15:12] rd[11:9] rs[8:6] rt[5:3] 000[2:0]
I-type             : op[15:12] rd[11:9] rs[8:6] imm6[5:0]
J-type             : op[15:12] cond[11:8] target[7:0]
X-type             : 1111[15:12] rd[11:9] rs[8:6] rt[5:3] func[2:0]
BEQ/BNE layout     : rs = bits [8:6], rt = bits [11:9] (rd field), imm6 = bits [5:0]
STORE layout       : data register rt = bits [11:9] (rd field), base rs = bits [8:6], imm6 = bits [5:0]
LOAD layout        : destination rd = bits [11:9], base rs = bits [8:6], imm6 = bits [5:0]
CMP layout         : rs = bits [8:6], rt = bits [5:3], rd field = 000, func = 011
```

## 2. Opcode map

All 16 opcodes are assigned in v2. Opcode values 0x0-0x7 and 0x9-0xC are
unchanged from Phase 1; 0x8 and 0xD were freed by turning MOV into a pseudo-
instruction and moving HALT into the extended group.

| Opcode | Mnemonic | Format | Assembly | Behavior | Flags read | Flags written |
|--------|----------|--------|----------|----------|------------|---------------|
| `0x0`  | ADD   | R | `add rd, rs, rt` | `rd <- rs + rt` | none | Z N C V |
| `0x1`  | SUB   | R | `sub rd, rs, rt` | `rd <- rs - rt` | none | Z N C V |
| `0x2`  | AND   | R | `and rd, rs, rt` | `rd <- rs & rt` | none | Z N, C=0 V=0 |
| `0x3`  | OR    | R | `or rd, rs, rt` | `rd <- rs \| rt` | none | Z N, C=0 V=0 |
| `0x4`  | NOT   | R | `not rd, rs` | `rd <- ~rs` (rt=0) | none | Z N, C=0 V=0 |
| `0x5`  | XOR   | R | `xor rd, rs, rt` | `rd <- rs ^ rt` | none | Z N, C=0 V=0 |
| `0x6`  | SHL   | R | `shl rd, rs` | `rd <- rs << 1` (rt=0) | none | Z N C V |
| `0x7`  | SHR   | R | `shr rd, rs` | `rd <- rs >> 1` (rt=0) | none | Z N C, V=0 |
| `0x8`  | LOAD  | I | `load rd, [rs + imm]` | `rd <- RAM[(rs + sext(imm)) mod 256]` | none | none |
| `0x9`  | LOADI | I | `loadi rd, imm` | `rd <- sext(imm6)` | none | none |
| `0xA`  | BEQ   | I | `beq rs, rt, label` | if `rs == rt` then `PC <- PC+1+sext(imm6)` | none | none |
| `0xB`  | BNE   | I | `bne rs, rt, label` | if `rs != rt` then `PC <- PC+1+sext(imm6)` | none | none |
| `0xC`  | JMP group | J | see §3 | conditional/absolute jumps and CALL | per condition | none |
| `0xD`  | STORE | I | `store rt, [rs + imm]` | `RAM[(rs + sext(imm)) mod 256] <- rt` | none | none |
| `0xE`  | ADDI  | I | `addi rd, rs, imm` | `rd <- rs + sext(imm6)` | none | Z N C V |
| `0xF`  | EXT   | X | see §4 | NOP, HALT, RET, CMP | per function | per function |

Pseudo-instructions (assembler only, no new opcode):

| Pseudo | Expansion | Notes |
|--------|-----------|-------|
| `mov rd, rs` | `add rd, rs, r0` | Writes the flags (ADD semantics). R0 supplies the zero. |
| `subi rd, rs, k` | `addi rd, rs, -k` | `k` must be -31..32 so that `-k` fits -32..31; otherwise a clear error. |
| `nop` | extended function 0 | Encoded `0xF000`; no architectural effect, PC+1. |

## 3. Jump group (opcode 0xC)

The four bits that were reserved/zero in the Phase 1 J-type instruction are now
the condition/operation code. All jump-group targets are **absolute 8-bit
addresses** (0..255), so they never depend on the branch's own address and do
not wrap as a side effect of encoding.

| cond | Mnemonic | Behavior | Condition / use |
|------|----------|----------|-----------------|
| `0x0` | JMP  | `PC <- target` | always |
| `0x1` | BZ   | `PC <- target` if taken | `Z = 1` (equal / result zero) |
| `0x2` | BNZ  | `PC <- target` if taken | `Z = 0` (not equal / result nonzero) |
| `0x3` | BCS / BHS | `PC <- target` if taken | `C = 1`; after CMP: unsigned `rs >= rt` (no borrow) |
| `0x4` | BCC / BLO | `PC <- target` if taken | `C = 0`; after CMP: unsigned `rs < rt` (borrow) |
| `0x5` | BN   | `PC <- target` if taken | `N = 1` (negative result) |
| `0x6` | BNN  | `PC <- target` if taken | `N = 0` (non-negative result) |
| `0x7` | BLT  | `PC <- target` if taken | `N != V`; after CMP: signed `rs < rt` |
| `0x8` | BGE  | `PC <- target` if taken | `N == V`; after CMP: signed `rs >= rt` |
| `0x9`-`0xE` | *reserved* | decode as NOP (PC+1) | future conditions |
| `0xF` | CALL | `R7 <- PC+1; PC <- target` | unconditional subroutine call |

`JMP` has its own absolute encoding; `JMP label` and the conditional branches
use the same 8-bit target field. `CALL` is the only jump-group operation that
writes a register (R7).

### Jump-group bit layout

```
JMP            0xC0tt   (cond=0, target=tt)
BZ             0xC1tt
BNZ            0xC2tt
BCS / BHS      0xC3tt
BCC / BLO      0xC4tt
BN             0xC5tt
BNN            0xC6tt
BLT            0xC7tt
BGE            0xC8tt
CALL           0xCFtt
```

## 4. Extended group (opcode 0xF)

The extended group reuses the R-type layout and its otherwise-unused low three
bits as a function field. This is the only place where HALT, RET and CMP live;
it leaves the jump group free for conditions and CALL.

| func | Mnemonic | Encoding | Behavior | Flags read | Flags written |
|------|----------|----------|----------|------------|---------------|
| `0x0` | NOP  | `0xF000` | no operation, PC+1 | none | none |
| `0x1` | HALT | `0xF001` | freeze PC; CPU stops | none | none |
| `0x2` | RET  | `0xF002` | `PC <- R7` | none | none |
| `0x3` | CMP  | `1111 000 rs rs rs rt rt rt 011` | compute `rs - rt`, set flags, **no register write** | none | Z N C V |
| `0x4`-`0x7` | *reserved* | | decode as NOP | none | none |

`CMP rs, rt` is SUB with `reg_write = 0`. The subtraction still goes through the
ALU, so the flags are exactly those of `sub r0, rs, rt` (without the R0 write).
The `rd` field is zero in CMP encodings.

Examples:

```
cmp r1, r2     ; 0xF053   (func=3, rs=1, rt=2)
ret            ; 0xF002
halt           ; 0xF001
nop            ; 0xF000
```

## 5. Flags

Four flags are stored in the flag register, reset to `0000`. They are written
only when an instruction has `FlagWrite = 1`.

- `Z` — result is zero
- `N` — result bit 7 (two's-complement sign)
- `C` — carry. For SUB/CMP, **C = 1 means no borrow** (ARM convention). SUB is
  computed as `A + not(B) + 1`, so the adder carry-out is exactly "no borrow".
- `V` — signed overflow

Per-class behavior (unchanged from Phase 1):

- **ADD, ADDI, SUB, CMP:** Z N C V from the arithmetic.
- **AND, OR, XOR, NOT:** Z N from the result; **C and V cleared**.
- **SHL:** `C = old bit 7`; `V = old bit7 xor new bit7` (sign changed); Z N.
- **SHR:** `C = old bit 0`; `V = 0`; Z N.
- **LOAD, STORE, LOADI, JMP, BZ/BNZ/BCS/BCC/BN/BNN/BLT/BGE, CALL, RET, HALT,
  NOP, BEQ, BNE:** do not write the flags.
  (MOV is a pseudo-instruction for ADD, so it *does* write flags and is not in
  this list. BEQ/BNE still use the dedicated comparator and do not touch flags.)

### Condition equations

| Mnemonic | Taken when | Meaning after `CMP rs, rt` |
|----------|------------|-----------------------------|
| JMP / CALL | always | unconditional |
| BZ  | `Z = 1` | `rs == rt` |
| BNZ | `Z = 0` | `rs != rt` |
| BCS / BHS | `C = 1` | unsigned `rs >= rt` |
| BCC / BLO | `C = 0` | unsigned `rs < rt` |
| BN  | `N = 1` | sign bit of `rs-rt`; not a full comparison |
| BNN | `N = 0` | sign bit clear; not a full comparison |
| BLT | `N xor V = 1` | signed `rs < rt` |
| BGE | `N xor V = 0` | signed `rs >= rt` |

The signed relations are exact for all 65,536 `(rs, rt)` pairs; this is proved
exhaustively by `alu_compare_tb.vhd`. `BN`/`BNN` only inspect the sign bit and
should not be used as a general "less than" test.

Example: the same bytes compare differently as unsigned and signed:

```
loadi r1, -2          ; r1 = 0xFE = 254 unsigned = -2 signed
loadi r2, 1
cmp   r1, r2
blo   unsigned_less    ; NOT taken: 254 < 1 is false
bhs   unsigned_ge      ; taken:     254 >= 1 is true
...
cmp   r1, r2
blt   signed_less      ; taken:     -2 < 1 is true
bge   signed_ge        ; NOT taken: -2 >= 1 is false
```

## 6. Immediates, branch targets and PC wrap

- **LOADI/ADDI `imm6`: sign-extended** to 8 bits, range **-32..+31**.
- **LOAD/STORE `imm6`: sign-extended address offset**, range -32..+31.
  Effective address = `(rs + sext(imm6)) mod 256`.
- **BEQ/BNE `imm6`: sign-extended PC-relative offset**, range -32..+31.
  Target = `(PC_of_branch + 1 + sext(imm6)) mod 256`. This is the Phase 1
  encoding, kept unchanged for compatibility.
- **Jump group (`JMP`, conditions, `CALL`): absolute 8-bit target** (0..255).
  This is simpler than PC-relative and is wrap-free: the label denotes the
  instruction address directly.
- **SUBI** is a pseudo-instruction: `subi rd, rs, k` = `addi rd, rs, -k`.
  The original `k` must be **-31..+32** so the negated immediate fits -32..+31.

### Program-counter wrap (intended)

The PC is exactly 8 bits; every PC update is modulo 256:

- `PC+1` wraps from `0xFF` to `0x00`.
- A taken BEQ/BNE computes `(PC+1+sext(imm6)) mod 256`, so a branch near `0xFF`
  can wrap forward to a low address, and a branch near `0x00` can wrap backward
  to a high address.
- Jump-group targets are absolute; `JMP 0xFF` executes the last ROM word.
- The ROM is HALT-filled beyond the program, so running off the end of a
  shorter program halts at the first filler word. If a program occupies all
  256 words there is no filler, and `PC+1` at `0xFF` wraps to `0x00` and
  restarts execution.

`cpu_edge_tb.vhd` asserts all of these cases.

## 7. Data RAM

- **Size:** 256 bytes of physical storage (8-bit address, 8-bit data), but
  only `0x00..0xEF` (240 bytes) are CPU data RAM. `0xF0..0xFF` is decoded as
  MMIO (section 8) and cannot be used as RAM.
- **Read:** asynchronous (combinational) from the addressed byte. This is
  required by the single-cycle datapath.
- **Write:** synchronous on the rising clock edge, only when `mem_write = 1`.
- **Address:** `(rs + sext(imm6)) mod 256`. `rs` is bits 8:6; `imm6` is bits
  5:0. Negative offsets and wrap-around are intentional.
- **LOAD rd, [rs+imm]:** `rd <- RAM[address]`; writes a register, not the flags.
- **STORE rt, [rs+imm]:** `RAM[address] <- rt`; the data register `rt` is
  encoded in the **rd field** bits 11:9 (the same trick as BEQ/BNE), because
  the 6-bit immediate occupies bits 5:0. STORE never writes a register.
- **Read-during-write:** an asynchronous read in the same cycle as a write
  returns the old byte; the new byte is visible after the rising edge.
- **Initial contents:** a VHDL generic `RAM_INIT : ram_init_t`. Entry `i` is
  the byte at address `i`; addresses not covered are zero. The assembler
  generates this generic from `.data` directives and rejects data that would
  reach into the MMIO region. No file I/O is used.
- Writes to R0 are ignored for every instruction, including LOAD. CALL writes
  R7 by hardware, never R0.

The assembler cannot materialize an arbitrary 8-bit address with a single
LOADI because the immediate is signed 6-bit (-32..31). Programs can use low RAM
addresses directly (`[r0+0]`..`[r0+31]`), build a base with shifts/adds, or use
a negative immediate (e.g. `[r0-32]` addresses 0xE0). This is a known
limitation, not a wrap exception.

## 8. I/O map (MMIO)

Phase 3 adds **memory-mapped I/O** without changing any instruction encoding.
The data address space is split as follows:

- **Data RAM:** `0x00..0xEF` (240 bytes).
- **MMIO:** `0xF0..0xFF` (16 addresses). The top 16 data-RAM cells are **not**
  available as RAM.
- `LOAD`/`STORE` keep exactly their ISA v2 semantics: the effective address is
  still `(rs + sext(imm6)) mod 256`. `cpu_top` decodes addresses
  `>= 0xF0` to `mmio` and all other addresses to `data_ram`. MMIO reads are
  combinational (so a LOAD still completes in one cycle); MMIO writes are
  synchronous on the rising edge.

| Address | Name | Access | Reset | Behavior |
|---------|------|--------|-------|----------|
| `0xF0` | `UART_TX` | W (read 0) | — | Write a byte to the 8N1 transmitter. A write while `UART_STATUS.tx_busy=1` is **ignored** (no queue, no overwrite). Reads return `0x00`. |
| `0xF1` | `UART_STATUS` | R | busy=0 | Bit 0 = `tx_busy`; bits 7:1 read 0. Writes are ignored. |
| `0xF2` | `GPIO_OUT` | W / R | `0x00` | 8-bit LED/output register. Readback returns the register. |
| `0xF3` | `GPIO_IN` | R | `0x00` | Two-flop-synchronized switches/buttons. Writes are ignored. |
| `0xF4` | `CYCLE_COUNT_LO` | R | `0x00` | Low byte of a free-running 8-bit cycle counter. Writes are ignored. |
| `0xF5..0xFF` | reserved | R | `0x00` | Reads return `0x00`; writes are ignored. |

Writes to read-only addresses are ignored. All MMIO behavior is synchronous to
the CPU clock and there are no interrupts.

### UART transmitter (`0xF0` / `0xF1`)

- 8N1: one start bit (`0`), eight data bits **LSB first**, one stop bit (`1`);
  idle line is high.
- Generics `CLK_FREQ` (Hz) and `BAUD` (bits/s). The integer divisor is
  `CLKS_PER_BIT = CLK_FREQ / BAUD`; the actual baud rate is
  `CLK_FREQ / CLKS_PER_BIT`. There is no fractional divider. A divisor below 2
  is rejected by an assertion.
- `tx_busy` goes high on the write edge and stays high for exactly ten bit
  periods (start + 8 data + stop). Software must poll `UART_STATUS` before the
  next write; there is no FIFO.
- The first write after reset is accepted. A write while busy has no effect and
  does not change the byte in flight.

### GPIO (`0xF2` / `0xF3`)

- `GPIO_OUT` is a plain 8-bit register, readable back, reset to `0x00`.
- `GPIO_IN` is asynchronous at the FPGA pin. It passes through a **two-flop
  synchronizer**. For a CPU `LOAD GPIO_IN` executing in cycle `c`, the value
  sampled is the external pin value scheduled at cycle `c-2`; a changed value
  becomes visible after two rising clock edges. Schedule changes
  are sampled on rising edges, and the last scheduled value holds. The initial
  and reset value of both synchronizer stages is `0x00`, so reads during the
  first two cycles after reset observe `0x00`. Writes to `GPIO_IN` are ignored.
  The golden model and RTL I/O-fuzz harness read the same whitespace-separated
  `cycle value` schedule file. It must start at cycle 0; cycles are strictly
  increasing in `0..255` and values are bytes in `0..255`. Base-0 integer
  notation is accepted, blank lines are ignored, and `#` begins a comment.
  With no schedule, the model holds the `--gpio-in` value from cycle 0.

### Cycle counter (`0xF4`)

- Free-running 8-bit counter, reset to `0x00`, incremented on every rising
  clock edge, including while the CPU is halted. Only the low byte is exposed;
  it wraps `0xFF -> 0x00`. Writes are ignored.

### Assembly symbols

The assembler predefines case-insensitive symbols for the I/O addresses:
`UART_TX=0xF0`, `UART_STATUS=0xF1`, `GPIO_OUT=0xF2`, `GPIO_IN=0xF3`,
`CYCLE_COUNT_LO=0xF4`. Because the ISA has only a signed 6-bit immediate/offset
field, these addresses are encoded through their signed equivalents
(`0xF0 -> -16`, etc.). They are accepted by `loadi` and as memory offsets:

```asm
        loadi r1, UART_STATUS       ; r1 = 0xF1
poll:   load  r2, [r1+0]            ; LOAD does not write flags
        cmp   r2, r0                ; so test the value explicitly
        bnz   poll
        loadi r1, UART_TX
        loadi r2, 0x0A              ; '\n'
        store r2, [r1+0]
```

Using an I/O symbol as a label, jump target or arithmetic immediate is an
assembler error.

### Consequences

- `.data` may only initialize `0x00..0xEF`; a directive that reaches `0xF0` or
  above is rejected. The VHDL `data_ram` still contains 256 physical bytes for
  debug, but CPU writes to `0xF0..0xFF` go to MMIO and never change those cells.
- Data structures, saved R7 links and buffers must stay below `0xF0`.
- `GPIO_IN` is read-only and synchronized; a program that changes the pin and
  reads it in the very next cycle may still see the old value.
- `CYCLE_COUNT_LO` is a free-running low byte; it is useful for timing tests,
  not as a stable time base unless software handles wrap.

## 9. CALL / RET convention

- **CALL target:** `R7 <- (PC+1) mod 256` (the link), then `PC <- target`.
  CALL does not read or write the flags. R7 is written unconditionally by
  hardware (the `rd` field is ignored for CALL).
- **RET:** `PC <- R7`. RET does not read or write the flags.
- The link is **single-level**. There is no hardware stack and no stack
  pointer, by design.
- A **nested call** must save and restore R7 in data RAM, for example:

  ```asm
  outer:  store r7, [r0+20]   ; save the caller's link
          call  inner         ; overwrites R7
          load  r7, [r0+20]   ; restore the caller's link
          ret
  ```

- A called subroutine that itself makes no calls may simply end with `ret`.
- `CALL` at address `0xFF` stores link `0x00`; `RET` to `0x00` is valid.

## 10. Encoding examples

```
add r1, r2, r3      ; 0000 001 010 011 000 = 0x0298
addi r1, r2, -1     ; 1110 001 010 111111 = 0xE2BF
load r3, [r4+7]     ; 1000 011 100 000111 = 0x8707
store r5, [r6+0]    ; 1101 101 110 000000 = 0xDB80
cmp r1, r2          ; 1111 000 001 010 011 = 0xF053
ret                 ; 1111 000 000 000 010 = 0xF002
halt                ; 1111 000 000 000 001 = 0xF001
nop                 ; 1111 000 000 000 000 = 0xF000
beq r5, r5, +1      ; 1010 101 101 000001 = 0xAB41
bne r1, r0, -2      ; 1011 000 001 111110 = 0xB07E
bz 0x10             ; 1100 0001 00010000     = 0xC110
blt 0x70            ; 1100 0111 01110000     = 0xC770
call 0x90           ; 1100 1111 10010000     = 0xCF90
jmp 0x80            ; 1100 0000 10000000     = 0xC080
```

## 11. Reset and visible state

- Reset is synchronous and active high.
- Reset zeroes the PC and the flags, suppresses register/RAM/flags writes
  during reset cycles, and resets the MMIO peripherals: GPIO_OUT and the GPIO
  input synchronizer to `0x00`, the cycle counter to `0x00`, and the UART to
  idle with `tx_busy=0`.
- The register file has no architectural reset; in simulation it is
  zero-initialized as a convenience. Programs must not rely on that.
- Data RAM is zero except for the `RAM_INIT` generic entries.
- HALT freezes the PC and raises `halted`; registers, flags and RAM keep their
  values and remain observable through the debug ports. The UART may still be
  transmitting, and the free-running cycle counter keeps counting after HALT.
- `dbg_pc`, `dbg_flags` (Z N C V) and `dbg_regs` expose the final state;
  `dbg_ram` exposes the 256 physical data-RAM bytes (including the unreachable
  `0xF0..0xFF` cells, which normal stores never modify).

## 12. Design decisions (and why)

| Decision | Choice | Rationale / alternative rejected |
|----------|--------|----------------------------------|
| Opcode-space reorganisation | MOV becomes `add rd,rs,r0`; HALT moves to EXT | frees 0x8 and 0xD for LOAD/STORE; MOV was already an ADD in hardware, and HALT needs no operand slot |
| LOAD opcode | 0x8 (old MOV) | keeps LOADI at 0x9, so the two load instructions are adjacent; minimal dispatch changes |
| STORE opcode | 0xD (old HALT) | HALT moved into the extended group, so its old slot is available |
| ADDI opcode | 0xE (previously reserved) | last free simple I-type opcode; reuses the existing ADD ALU path |
| Extended group | opcode 0xF, function in bits 2:0 | those 3 bits were already unused in R-type; gives 8 functions with no new format |
| Jump group | opcode 0xC, condition/op in bits 11:8 | those 4 bits were documented zero in Phase 1; gives 16 operations, enough for JMP + 8 conditions + CALL + reserved |
| `JMP` remains a distinct cond code | cond 0 | Phase 1 `JMP` opcode/encoding is unchanged (0xC0tt) |
| MOV as pseudo | `add rd,rs,r0` | no opcode cost; exact Phase 1 data result, but MOV now writes flags. Accepted and documented because no Phase 1 program relies on MOV preserving flags |
| SUBI as pseudo | `addi rd,rs,-k` | no opcode cost; range check catches the one unrepresentable case `k = -32` |
| New branch targets | absolute 8-bit | simplest, position-independent labels, no offset range/wrap confusion; BEQ/BNE keep their legacy relative form for compatibility |
| BEQ/BNE target | PC-relative sext imm6 (unchanged) | Phase 1 compatibility; only 6 bits exist beside two register fields |
| CMP | EXT func 3, SUB with `reg_write=0` | reuses the ALU and yields exactly SUB's Z/N/C/V; no second comparator or flag path |
| Condition decode | combinational `branch_cond` (flags + 4-bit code) | keeps PC logic small and independently testable; exhaustive TB |
| STORE data register | rd field bits 11:9 | the immediate occupies 5:0 and rs is the base; same proven trick as BEQ/BNE |
| Data RAM | 256 x 8 physical storage; 0x00..0xEF CPU-visible, 0xF0..0xFF MMIO | matches single-cycle timing; address arithmetic reuses the ALU's ADD; see section 8 |
| RAM address wrap | `(rs + sext(imm6)) mod 256` | 8-bit address arithmetic is natural and cheap; documented |
| RAM init | VHDL generic `RAM_INIT` from `.data` | same file-I/O-free flow as ROM; reproducible in any simulator |
| CALL/RET link | R7, one level | no stack pointer/interrupt state in a single-cycle educational core; nested calls save R7 explicitly |
| R0 in memory ops | still hardwired zero; LOAD to R0 ignored | consistent with the register file contract; tested |
| Reserved jump conds / EXT funcs | decode as NOP | forward-compatible and cannot hang the CPU |
| HALT/Pseudo NOP encodings | `0xF001`, `0xF000` | HALT moved out of 0xD; NOP is a real no-op so `.org` gaps and padding are safe |
| ROM fill | HALT `0xF001` above the program | running off the end stops the CPU; `.org` gaps are NOP-filled |
| PC wrap | modulo 256, intended | 8-bit PC; asserted by `cpu_edge_tb` |
| MMIO placement | top 16 data addresses `0xF0..0xFF` | reuses unmodified LOAD/STORE and a 240-byte RAM window; no new instructions or address space |
| I/O read timing | combinational, like data RAM | keeps LOAD single-cycle; write remains synchronous |
| UART write while busy | ignored (no queue, no overwrite) | smallest hardware and clearest contract; software must poll `UART_STATUS`; tested at UART, MMIO and CPU level |
| UART baud divisor | integer `CLK_FREQ / BAUD` | avoids fractional-divider complexity; the resulting baud is documented and sufficient for a demo |
| UART_TX reads | return `0x00` | write-only register; avoids implying a readable transmit buffer |
| GPIO_IN | two-flop synchronizer | asynchronous FPGA pins need metastability protection; two cycles of latency is documented and tested |
| Cycle counter | free-running 8-bit low byte, reset to 0 | minimal timer for demos/tests; wraps by design, no interrupts |
| Reserved I/O reads | return `0x00`, writes ignored | deterministic behavior, no bus errors or hangs |
| `.data` into MMIO | assembler error | prevents silently losing initialized data; the hardware never writes RAM above `0xEF` |
| I/O assembly symbols | predefined names encoded as signed offsets | keeps the ISA's signed 6-bit immediate/offset unchanged while making programs readable |

## 13. Migration notes from Phase 1

- Existing opcodes 0x0-0x7, 0x9, 0xA, 0xB and 0xC keep their encodings.
- `HALT` changes from `0xD000` to `0xF001`; `MOV` changes from opcode 0x8 to
  `ADD` (`0x0700` for `mov r3,r4` instead of `0x8700`) and now writes flags.
- The Phase 1 programs `sum1to10` and `shift_branch` still produce the same
  results; `sum1to10` is simplified with ADDI. The assembler tests, ROM
  packages and `cpu_tb` were regenerated/updated accordingly.
- BEQ/BNE's register-comparator behavior is unchanged.
