#!/usr/bin/env python3
"""MiniCPU-8 two-pass assembler (Python 3, no external dependencies).

Usage:
  python3 tools/assembler.py PROGRAM.asm                # hex words to stdout
  python3 tools/assembler.py PROGRAM.asm --vhdl OUT.vhd # VHDL ROM+RAM packages
  python3 tools/assembler.py PROGRAM.asm --hex OUT.hex  # hex file

Syntax (see docs/ISA.md):
  add/sub/and/or/xor rd, rs, rt      R-type
  not/shl/shr         rd, rs         R-type (rt = 0)
  mov                 rd, rs         pseudo: add rd, rs, r0 (writes flags)
  addi                rd, rs, imm    imm in -32..31 (sign-extended)
  subi                rd, rs, k      pseudo: addi rd, rs, -k (k in -31..32)
  load                rd, [rs+imm]   data RAM read  (imm -32..31)
  store               rt, [rs+imm]   data RAM write (rt goes in the rd field)
  loadi               rd, imm        imm in -32..31
  cmp                 rs, rt         flags only, no register write
  beq/bne             rs, rt, label  PC-relative, offset -32..31
  jmp/bz/bnz/bcs/bhs/bcc/blo/bn/bnn/blt/bge target
                                     absolute target 0..255
  call                target         R7 <- PC+1, absolute target
  ret / halt / nop                   extended group functions
  .org ADDR                          set ROM address (gaps NOP-filled)
  .data ADDR, V, V, ...              initialize data RAM (does not use ROM)
Labels: "name:" (own line or before an instruction). Case-insensitive
mnemonics/labels/registers. Comments: start with ";", "#", or "--".
Errors are reported as "assembler: error: line N: message" and exit(1).
"""
import argparse
import os
import re
import sys
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# ISA v2 tables.  Keep these in sync with minicpu_pkg.vhd and docs/ISA.md;
# tools/check_consistency.py enforces that automatically.
# ---------------------------------------------------------------------------
OP_ADD, OP_SUB, OP_AND, OP_OR = 0x0, 0x1, 0x2, 0x3
OP_NOT, OP_XOR, OP_SHL, OP_SHR = 0x4, 0x5, 0x6, 0x7
OP_LOAD, OP_LOADI, OP_BEQ, OP_BNE = 0x8, 0x9, 0xA, 0xB
OP_JMP, OP_STORE, OP_ADDI, OP_EXT = 0xC, 0xD, 0xE, 0xF

R3 = {"add": OP_ADD, "sub": OP_SUB, "and": OP_AND, "or": OP_OR,
      "xor": OP_XOR}                                       # rd, rs, rt
R2 = {"not": OP_NOT, "shl": OP_SHL, "shr": OP_SHR}         # rd, rs
RI = {"loadi": OP_LOADI}                                   # rd, imm6
BR = {"beq": OP_BEQ, "bne": OP_BNE}                        # rs, rt, rel. label

# Extended-group function codes (low 3 bits of opcode 0xF).
FUNC = {"nop": 0x0, "halt": 0x1, "ret": 0x2, "cmp": 0x3}

# Jump-group condition/operation codes (bits 11:8 of opcode 0xC).
COND = {
    "jmp": 0x0,
    "bz": 0x1, "bnz": 0x2,
    "bcs": 0x3, "bhs": 0x3,       # aliases: unsigned >= (C=1)
    "bcc": 0x4, "blo": 0x4,       # aliases: unsigned <  (C=0)
    "bn": 0x5, "bnn": 0x6,
    "blt": 0x7, "bge": 0x8,
    "call": 0xF,
}
ABS_COND = {"jmp", "bz", "bnz", "bcs", "bhs", "bcc", "blo",
            "bn", "bnn", "blt", "bge", "call"}

NOP_WORD = (OP_EXT << 12) | FUNC["nop"]
HALT_WORD = (OP_EXT << 12) | FUNC["halt"]

# Every opcode constant exposed for the consistency checker.
OPCODES = {
    "ADD": OP_ADD, "SUB": OP_SUB, "AND": OP_AND, "OR": OP_OR,
    "NOT": OP_NOT, "XOR": OP_XOR, "SHL": OP_SHL, "SHR": OP_SHR,
    "LOAD": OP_LOAD, "LOADI": OP_LOADI, "BEQ": OP_BEQ, "BNE": OP_BNE,
    "JMP": OP_JMP, "STORE": OP_STORE, "ADDI": OP_ADDI, "EXT": OP_EXT,
}

# Normative layout strings (docs/ISA.md contains the same text).
BEQ_BNE_LAYOUT = "rs = bits [8:6], rt = bits [11:9] (rd field), imm6 = bits [5:0]"
STORE_LAYOUT = "data register rt = bits [11:9] (rd field), base rs = bits [8:6], imm6 = bits [5:0]"
LOAD_LAYOUT = "destination rd = bits [11:9], base rs = bits [8:6], imm6 = bits [5:0]"

LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*")
REG_RE = re.compile(r"^[rR]([0-7])$")
MEM_RE = re.compile(
    r"^\[\s*([rR][0-7])\s*(?:([+-])\s*(0[xX][0-9A-Fa-f]+|[+-]?[0-9]+))?\s*\]$")
INT_RE = re.compile(r"^[+-]?(?:0[xX][0-9A-Fa-f]+|[0-9]+)$")
NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class AsmError(Exception):
    def __init__(self, lineno, msg):
        super().__init__(f"assembler: error: line {lineno}: {msg}")


@dataclass
class Instr:
    lineno: int
    mnem: str
    ops: list
    addr: int


@dataclass
class Result:
    words: list
    ram: list
    labels: dict = field(default_factory=dict)


def reg(tok, lineno):
    m = REG_RE.match(tok)
    if not m:
        raise AsmError(lineno, f"expected register r0..r7, got '{tok}'")
    return int(m.group(1))


def parse_int(tok, lineno, what):
    if not INT_RE.match(tok):
        raise AsmError(lineno, f"bad number '{tok}' for {what}")
    return int(tok, 0)


def num(tok, lineno, lo, hi, what):
    v = parse_int(tok, lineno, what)
    if not lo <= v <= hi:
        raise AsmError(lineno, f"{what} {v} out of range {lo}..{hi}")
    return v


def strip_comment(line):
    for c in (";", "#", "--"):
        line = line.split(c)[0]
    return line


def split_operands(rest, lineno):
    if not rest:
        return []
    if "," in rest:
        ops = [p.strip() for p in rest.split(",")]
        if any(p == "" for p in ops):
            raise AsmError(lineno, "empty operand (stray comma?)")
        return ops
    return rest.split()


def split_line(code):
    parts = code.split(None, 1)
    mnem = parts[0].lower()
    rest = parts[1].strip() if len(parts) > 1 else ""
    return mnem, rest


def parse_mem(op, lineno):
    """Parse '[rs + imm]' -> (rs, imm6), imm in -32..31."""
    m = MEM_RE.match(op)
    if not m:
        raise AsmError(lineno, f"expected memory operand '[rs + imm]', got '{op}'")
    base = reg(m.group(1), lineno)
    if m.group(3) is None:
        imm = 0
    else:
        sign = 1 if m.group(2) == "+" else -1
        imm = sign * parse_int(m.group(3), lineno, "memory offset")
    if not -32 <= imm <= 31:
        raise AsmError(lineno, f"memory offset {imm} out of range -32..31")
    return base, imm


def abs_target(tok, labels, lineno):
    """Absolute jump/branch/call target: label or 0..255 numeric address."""
    if NAME_RE.match(tok):
        name = tok.lower()
        if name not in labels:
            raise AsmError(lineno, f"undefined label '{tok}'")
        addr = labels[name]
        if not 0 <= addr <= 255:
            raise AsmError(lineno, f"target label '{tok}' resolves to {addr}, "
                                   f"outside 0..255")
        return addr
    return num(tok, lineno, 0, 255, "jump target")


def rel_offset(tok, labels, lineno, addr):
    """BEQ/BNE offset: label (computed) or a raw signed numeric offset."""
    if NAME_RE.match(tok):
        name = tok.lower()
        if name not in labels:
            raise AsmError(lineno, f"undefined label '{tok}'")
        off = labels[name] - (addr + 1)
        if not -32 <= off <= 31:
            raise AsmError(lineno, f"branch to '{tok}' out of range "
                                   f"(offset {off}, allowed -32..31)")
        return off
    return num(tok, lineno, -32, 31, "branch offset")


def parse_source(text):
    return [strip_comment(raw).strip() for raw in text.splitlines()]


def first_pass(text):
    """Assign ROM addresses, collect labels and data directives."""
    instrs = []
    data = []          # (lineno, address, value)
    labels = {}
    pc = 0
    for lineno, code in enumerate(parse_source(text), 1):
        if not code:
            continue
        # Peel every leading label; each binds to the current ROM address.
        while True:
            m = LABEL_RE.match(code)
            if not m:
                break
            name = m.group(1).lower()
            if name in labels:
                raise AsmError(lineno, f"duplicate label '{name}'")
            labels[name] = pc
            code = code[m.end():].strip()
        if not code:
            continue

        mnem, rest = split_line(code)
        ops = split_operands(rest, lineno)

        if mnem == ".org":
            if len(ops) != 1:
                raise AsmError(lineno, ".org needs exactly one address")
            addr = num(ops[0], lineno, 0, 255, ".org address")
            if addr < pc:
                raise AsmError(lineno, f".org cannot move backwards "
                                       f"(current address {pc}, requested {addr})")
            pc = addr
            continue

        if mnem == ".data":
            if len(ops) < 2:
                raise AsmError(lineno, ".data needs an address and at least one byte")
            base = num(ops[0], lineno, 0, 255, ".data address")
            for i, tok in enumerate(ops[1:]):
                v = parse_int(tok, lineno, ".data byte")
                if not -128 <= v <= 255:
                    raise AsmError(lineno, f".data byte {v} out of range -128..255")
                if base + i > 255:
                    raise AsmError(lineno, f".data runs past address 255 "
                                           f"(starts at {base}, {len(ops)-1} bytes)")
                data.append((lineno, base + i, v & 0xFF))
            continue

        if mnem.startswith("."):
            raise AsmError(lineno, f"unknown directive '{mnem}'")

        instrs.append(Instr(lineno, mnem, ops, pc))
        pc += 1
        if pc > 256:
            raise AsmError(lineno, "program exceeds 256 instruction words")

    if not instrs:
        raise AsmError(1, "program is empty")
    return instrs, data, labels


def encode(instr, labels):
    lineno, mnem, ops, addr = instr.lineno, instr.mnem, instr.ops, instr.addr

    if mnem in R3:
        if len(ops) != 3:
            raise AsmError(lineno, f"{mnem} needs 3 operands: {mnem} rd, rs, rt")
        rd, rs, rt = (reg(ops[0], lineno), reg(ops[1], lineno), reg(ops[2], lineno))
        return (R3[mnem] << 12) | (rd << 9) | (rs << 6) | (rt << 3)

    if mnem in R2:
        if len(ops) != 2:
            raise AsmError(lineno, f"{mnem} needs 2 operands: {mnem} rd, rs")
        rd, rs = reg(ops[0], lineno), reg(ops[1], lineno)
        return (R2[mnem] << 12) | (rd << 9) | (rs << 6)

    if mnem == "mov":                            # pseudo: add rd, rs, r0
        if len(ops) != 2:
            raise AsmError(lineno, "mov needs 2 operands: mov rd, rs")
        rd, rs = reg(ops[0], lineno), reg(ops[1], lineno)
        return (OP_ADD << 12) | (rd << 9) | (rs << 6)

    if mnem == "loadi":
        if len(ops) != 2:
            raise AsmError(lineno, "loadi needs 2 operands: loadi rd, imm")
        rd = reg(ops[0], lineno)
        imm = num(ops[1], lineno, -32, 31, "loadi immediate")
        return (OP_LOADI << 12) | (rd << 9) | (imm & 0x3F)

    if mnem == "addi":
        if len(ops) != 3:
            raise AsmError(lineno, "addi needs 3 operands: addi rd, rs, imm")
        rd, rs = reg(ops[0], lineno), reg(ops[1], lineno)
        imm = num(ops[2], lineno, -32, 31, "addi immediate")
        return (OP_ADDI << 12) | (rd << 9) | (rs << 6) | (imm & 0x3F)

    if mnem == "subi":
        if len(ops) != 3:
            raise AsmError(lineno, "subi needs 3 operands: subi rd, rs, k")
        rd, rs = reg(ops[0], lineno), reg(ops[1], lineno)
        k = parse_int(ops[2], lineno, "subi immediate")
        if not -31 <= k <= 32:
            raise AsmError(lineno, f"subi immediate {k} out of range -31..32 "
                                   f"(subi is addi with the immediate negated)")
        imm = -k
        return (OP_ADDI << 12) | (rd << 9) | (rs << 6) | (imm & 0x3F)

    if mnem == "load":
        if len(ops) != 2:
            raise AsmError(lineno, "load needs 2 operands: load rd, [rs + imm]")
        rd = reg(ops[0], lineno)
        rs, imm = parse_mem(ops[1], lineno)
        return (OP_LOAD << 12) | (rd << 9) | (rs << 6) | (imm & 0x3F)

    if mnem == "store":
        if len(ops) != 2:
            raise AsmError(lineno, "store needs 2 operands: store rt, [rs + imm]")
        rt = reg(ops[0], lineno)
        rs, imm = parse_mem(ops[1], lineno)
        # The data register goes in the rd field (bits 11:9).
        return (OP_STORE << 12) | (rt << 9) | (rs << 6) | (imm & 0x3F)

    if mnem in BR:
        if len(ops) != 3:
            raise AsmError(lineno, f"{mnem} needs 3 operands: {mnem} rs, rt, label")
        rs, rt = reg(ops[0], lineno), reg(ops[1], lineno)
        off = rel_offset(ops[2], labels, lineno, addr)
        return (BR[mnem] << 12) | (rt << 9) | (rs << 6) | (off & 0x3F)

    if mnem in ABS_COND:
        if len(ops) != 1:
            raise AsmError(lineno, f"{mnem} needs 1 operand: {mnem} target")
        target = abs_target(ops[0], labels, lineno)
        return (OP_JMP << 12) | (COND[mnem] << 8) | target

    if mnem == "cmp":
        if len(ops) != 2:
            raise AsmError(lineno, "cmp needs 2 operands: cmp rs, rt")
        rs, rt = reg(ops[0], lineno), reg(ops[1], lineno)
        return (OP_EXT << 12) | (rs << 6) | (rt << 3) | FUNC["cmp"]

    if mnem in FUNC:                             # nop / halt / ret
        if len(ops) != 0:
            raise AsmError(lineno, f"{mnem} takes no operands")
        return (OP_EXT << 12) | FUNC[mnem]

    raise AsmError(lineno, f"unknown instruction '{mnem}'")


def assemble_with_data(text):
    instrs, data, labels = first_pass(text)
    length = max(i.addr for i in instrs) + 1
    words = [NOP_WORD] * length
    for instr in instrs:
        if not 0 <= instr.addr <= 255:
            raise AsmError(instr.lineno, f"instruction address {instr.addr} "
                                         f"outside 0..255")
        words[instr.addr] = encode(instr, labels)

    seen = {}
    for lineno, address, value in data:
        if address in seen:
            raise AsmError(lineno, f"data address {address} already initialized "
                                   f"(first at line {seen[address]})")
        seen[address] = lineno
    ram = []
    if data:
        ram = [0] * (max(a for _, a, _ in data) + 1)
        for _, address, value in data:
            ram[address] = value
    return Result(words=words, ram=ram, labels=labels)


def assemble(text):
    """Backwards-compatible API: return just the ROM words."""
    return assemble_with_data(text).words


def to_vhdl(words, asm_path, ram=None):
    """Emit one VHDL file with <base>_rom (PROG) and <base>_ram (INIT)."""
    if isinstance(words, Result):
        ram = words.ram if ram is None else ram
        words = words.words
    ram = list(ram) if ram else [0x00]
    base = os.path.splitext(os.path.basename(asm_path))[0]
    base = re.sub(r"[^a-z0-9_]", "", base.lower())
    pkg = base + "_rom"
    ram_pkg = base + "_ram"
    lines = [
        f"-- {pkg}.vhd : GENERATED from {os.path.basename(asm_path)} by tools/assembler.py",
        "-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py "
        f"{os.path.basename(asm_path)} --vhdl {pkg}.vhd",
        "library ieee;",
        "use ieee.std_logic_1164.all;",
        "use work.minicpu_pkg.all;",
        "",
        f"package {pkg} is",
        "  constant PROG : rom_t := (",
    ]
    for i in range(0, len(words), 4):
        if len(words) == 1:
            chunk = f'0 => x"{words[0]:04X}"'
        else:
            chunk = ", ".join(f'x"{w:04X}"' for w in words[i:i + 4])
        tail = "," if i + 4 < len(words) else ""
        lines.append(f"    {chunk}{tail}")
    lines += [");", f"end package {pkg};", ""]
    # A VHDL context clause applies to the immediately following design unit,
    # so the second package needs its own library/use clauses.
    lines += [
        "library ieee;",
        "use ieee.std_logic_1164.all;",
        "use work.minicpu_pkg.all;",
        "",
        f"package {ram_pkg} is",
        "  constant INIT : ram_init_t := (",
    ]
    # Named associations resolve the element type of the unconstrained array
    # even for a single element (a bare x"00" aggregate is ambiguous in VHDL).
    for i in range(0, len(ram), 8):
        chunk = ", ".join(f'{j} => x"{ram[j]:02X}"'
                          for j in range(i, min(i + 8, len(ram))))
        tail = "," if i + 8 < len(ram) else ""
        lines.append(f"    {chunk}{tail}")
    lines += [");", f"end package {ram_pkg};", ""]
    return "\n".join(lines), pkg


def main():
    ap = argparse.ArgumentParser(description="MiniCPU-8 assembler")
    ap.add_argument("input", help=".asm source file")
    ap.add_argument("--vhdl", metavar="FILE", help="write VHDL ROM+RAM packages")
    ap.add_argument("--hex", metavar="FILE", help="write hex word list")
    args = ap.parse_args()

    try:
        with open(args.input) as f:
            text = f.read()
        result = assemble_with_data(text)
    except AsmError as e:
        sys.exit(str(e))
    except OSError as e:
        sys.exit(f"assembler: error: cannot read {args.input}: {e}")

    hex_lines = [f"{w:04X}" for w in result.words]
    if args.vhdl:
        src, _ = to_vhdl(result, args.input, result.ram)
        with open(args.vhdl, "w") as f:
            f.write(src)
        print(f"{args.input}: {len(result.words)} words, "
              f"{len(result.ram)} RAM bytes -> {args.vhdl}", file=sys.stderr)
    if args.hex:
        with open(args.hex, "w") as f:
            f.write("\n".join(hex_lines) + "\n")
        print(f"{args.input}: {len(result.words)} words -> {args.hex}", file=sys.stderr)
    if not args.vhdl and not args.hex:
        print("\n".join(hex_lines))


if __name__ == "__main__":
    main()
