# MiniCPU-8 Instruction Set Architecture (Phase 1)

MiniCPU-8 is an educational 8-bit single-cycle CPU.

- **Data path:** 8 bits
- **Program Counter:** 8 bits (addresses 0..255 instructions)
- **Registers:** 8 x 8-bit registers `R0..R7`. **R0 is hardwired to zero**: it always
  reads as `0x00` and writes to it are ignored.
- **Instructions:** 16-bit fixed width
- **Memory:** instruction ROM only (no LOAD/STORE, no RAM in Phase 1)
- **Execution:** one instruction per clock cycle (single-cycle)

## 1. Instruction formats

Three formats share the upper nibble as opcode; field layout differs per format.

```
R-type : [ op:4 | rd:3 | rs:3 | rt:3 | 0:3 ]   register-register
I-type : [ op:4 | rd:3 | rs:3 | imm:6       ]   immediate / branch
J-type : [ op:4 | 0:4 |        target:8     ]   absolute jump
        15   12 11  9 8   6 5   3 2         0
```

- `rd` = destination register number
- `rs`, `rt` = source register numbers
- `imm` = 6-bit immediate (see sign extension rules below)
- `target` = absolute instruction address 0..255
- Bits marked `0` are ignored by hardware and must be 0 (the assembler emits 0).

## 2. Opcodes

| Opcode | Mnemonic | Format | Assembly            | Behavior                                    | Flags   |
|--------|----------|--------|---------------------|---------------------------------------------|---------|
| `0x0`  | ADD      | R      | `add rd, rs, rt`    | `rd <- rs + rt`                             | Z N C V |
| `0x1`  | SUB      | R      | `sub rd, rs, rt`    | `rd <- rs - rt`                             | Z N C V |
| `0x2`  | AND      | R      | `and rd, rs, rt`    | `rd <- rs & rt`                             | Z N, C=0, V=0 |
| `0x3`  | OR       | R      | `or  rd, rs, rt`    | `rd <- rs \| rt`                            | Z N, C=0, V=0 |
| `0x4`  | NOT      | R      | `not rd, rs`        | `rd <- ~rs` (rt ignored, encoded 0)         | Z N, C=0, V=0 |
| `0x5`  | XOR      | R      | `xor rd, rs, rt`    | `rd <- rs ^ rt`                             | Z N, C=0, V=0 |
| `0x6`  | SHL      | R      | `shl rd, rs`        | `rd <- rs << 1` (1-bit, logical)            | Z N C V (see §4) |
| `0x7`  | SHR      | R      | `shr rd, rs`        | `rd <- rs >> 1` (1-bit, logical)            | Z N C, V=0     |
| `0x8`  | MOV      | R      | `mov rd, rs`        | `rd <- rs` (encoded as ADD with rt=R0)      | none    |
| `0x9`  | LOADI    | I      | `loadi rd, imm`     | `rd <- sext(imm6)`                          | none    |
| `0xA`  | BEQ      | I      | `beq rs, rt, label` | if `rs == rt` then PC <- PC+1+sext(imm6)    | none    |
| `0xB`  | BNE      | I      | `bne rs, rt, label` | if `rs != rt` then PC <- PC+1+sext(imm6)    | none    |
| `0xC`  | JMP      | J      | `jmp label`         | `PC <- target` (absolute, 0..255)           | none    |
| `0xD`  | HALT     | -      | `halt`              | PC frozen, CPU stops                         | none    |
| `0xE`  | *reserved* | -    |                     | decodes as NOP (no writes, PC+1)            | none    |
| `0xF`  | *reserved* | -    |                     | decodes as NOP (no writes, PC+1)            | none    |

Notes:

- **Branch operand placement:** in BEQ/BNE the two compared registers are `rs`
  (bits 8:6) and `rt`, which is stored in the **`rd` field** (bits 11:9), because
  the 6-bit immediate occupies bits 5:0. The assembler places operands correctly.
  Normative layout marker: `BEQ/BNE layout: rs = bits [8:6], rt = bits [11:9] (rd field), imm6 = bits [5:0]`.
- **Branch semantics are register-compare, not flag-based:** the CPU contains a
  dedicated 8-bit equality comparator, so branches do not touch the flags and do
  not need a preceding compare instruction.
- **MOV** is encoded exactly as `add rd, rs, r0` but with the MOV opcode; since R0
  reads as zero, `rs + 0 = rs`. MOV does not write the flags (FlagWrite=0 for MOV,
  unlike ADD).
- **Reserved opcodes** are decoded as NOPs (all control outputs 0) so future
  extensions and hand-patched ROMs do not hang the CPU.

## 3. Immediates and branch targets

- **LOADI `imm6`: sign-extended** to 8 bits. Range -32..+31. This is the standard
  choice (MIPS/ARM-like) and lets programs materialize negative constants such as
  -1 in a single instruction. Zero-extension would make e.g. `0xFF` unrepresentable
  anyway (6 bits can only hold 0..63), so sign extension loses nothing for small
  positives and gains negatives.
- **BEQ/BNE `imm6`: sign-extended, PC-relative.** Target = address of branch + 1
  + sext(imm6). Range -32..+31 instructions around the branch. PC-relative keeps
  the encoding position-independent for these short forward/backward loops.
- **JMP: absolute 8-bit target.** The J-type format spends all 12 non-opcode bits
  on the target; the low 8 bits load the PC directly (the upper 4 must be 0).
  Absolute encoding makes `jmp` usable as a "go anywhere" jump, complementing the
  short-range conditional branches.
- All additions to the PC are modulo 256 (8-bit PC).

### Program-counter wrap (intended behaviour)

The PC is exactly 8 bits. Every PC update is modulo 256:

- `PC+1` wraps from `0xFF` to `0x00`.
- A taken BEQ/BNE computes `PC+1+sext(imm6)` modulo 256, so a branch near
  `0xFF` can wrap forward to a low address and a branch near `0x00` can wrap
  backward to a high address.
- `JMP` loads an absolute 8-bit target; `JMP 0xFF` executes the instruction in
  the last ROM word.

The ROM is 256 words and is filled with HALT beyond the program, so running
past the end of a shorter program halts at the first filler word. A program
that occupies all 256 words has no filler: `PC+1` at `0xFF` wraps to `0x00`
and execution restarts. This is documented, intentional wrap-around.

## 4. Flags

Four flags, stored in a flag register (reset to 0000):

- `Z` result is zero
- `N` result bit 7 is set
- `C` carry. For SUB, **C=1 means no borrow** (ARM convention; SUB is computed as
  `A + not(B) + 1`, so carry-out of the adder is exactly "no borrow")
- `V` signed overflow

Per-class flag behavior:

- **ADD/SUB:** Z N C V all computed from the arithmetic.
- **Logic (AND, OR, XOR, NOT):** Z and N from the result; **C and V are cleared**.
  Logic ops have no meaningful carry or overflow, so they are defined as 0 rather
  than left unchanged (keeps the flag register simple: one write-enable for all 4).
- **SHL:** `C = old bit 7` (the bit shifted out); `V = old bit7 xor new bit7`
  (set when the sign of the signed value changed -- true overflow for x2);
  Z, N from the result.
- **SHR:** `C = old bit 0` (bit shifted out); `V = 0` (logical right shift cannot
  overflow); Z, N from the result.
- **MOV, LOADI, JMP, BEQ, BNE, HALT, NOP:** no flag change.

## 5. Encoding examples

```
add r1, r2, r3    ; op=0  rd=1 rs=2 rt=3 -> 0000 001 010 011 000 = 0x0298
loadi r1, -1      ; op=9  rd=1 imm=0x3F  -> 1001 001 000 111111 = 0x923F
beq  r5, r5, +1   ; op=A  rt=5 rs=5 imm=1 -> 1010 101 101 000001 = 0xAB41
jmp  8            ; op=C  target=8        -> 1100 0000 00001000   = 0xC008
halt              ; op=D                   -> 1100... = 0xD000
```

## 6. Restart and visible state

- Reset (synchronous, active high) zeroes the PC and the flags.
- The register file has **no reset**; after power-up registers other than R0 are
  undefined (zero-initialized in simulation as a convenience -- programs must not
  rely on this).
- On HALT the PC stops incrementing and `halted` goes high; flags and registers
  keep their values and remain observable for checking.

## 7. Design decisions summary (and why)

| Decision | Choice | Rationale |
|---|---|---|
| Immediate extension | sign-extend | enables negative constants; costs one gate; MIPS/ARM precedent |
| Branch encoding | PC-relative, sext imm6 | only 6 bits available next to 2 register fields; loops are short |
| JMP encoding | absolute 8-bit | uses all spare bits; simple "jump anywhere" semantics |
| Branch condition | dedicated comparator on rs vs rt | avoids clobbering flags; no CMP instruction needed |
| Logic flags | C=V=0 | deterministic, simple hardware; documented per instruction |
| SHL flags | C=shifted-out bit, V=sign-changed | ARM-like, educational; exact 1-bit shift makes V well-defined |
| SHR flags | C=shifted-out bit, V=0 | logical shift right cannot overflow |
| MOV implementation | ADD with rt=R0, FlagWrite=0 | R0-is-zero makes MOV free in hardware; distinct mnemonic kept for readability |
| ROM loading | VHDL generic `INIT : rom_t`, generated by the assembler | works with any simulator (NVC included), no file I/O at elaboration, each testbench can embed its own program |
| ROM beyond program | filled with HALT (0xD000) | running off the end stops the CPU instead of executing garbage |
| Reserved opcodes | decode as NOP | forward-compatible, cannot hang |
