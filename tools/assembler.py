#!/usr/bin/env python3
"""MiniCPU-8 two-pass assembler (Python 3, no external dependencies).

Usage:
  python3 tools/assembler.py PROGRAM.asm                # hex words to stdout
  python3 tools/assembler.py PROGRAM.asm --vhdl OUT.vhd # VHDL ROM package
  python3 tools/assembler.py PROGRAM.asm --hex OUT.hex  # hex file

Syntax (see docs/ISA.md):
  add/sub/and/or/xor rd, rs, rt     R-type
  not/shl/shr/mov    rd, rs         R-type (rt = 0)
  loadi              rd, imm        imm in -32..31 (sign-extended)
  beq/bne            rs, rt, label  PC-relative, offset -32..31
  jmp                label|addr     absolute 0..255
  halt
Labels: "name:" (own line or before an instruction). Case-insensitive
mnemonics/labels/registers. Comments: start with ";", "#", or "--".
Errors are reported as "assembler: error: line N: message" and exit(1).
"""
import argparse
import os
import re
import sys

# mnemonic -> opcode
R3 = {"add": 0x0, "sub": 0x1, "and": 0x2, "or": 0x3, "xor": 0x5}  # rd, rs, rt
R2 = {"not": 0x4, "shl": 0x6, "shr": 0x7, "mov": 0x8}             # rd, rs
RI = {"loadi": 0x9}                                               # rd, imm6
BR = {"beq": 0xA, "bne": 0xB}                                     # rs, rt, target
OP_JMP, OP_HALT = 0xC, 0xD

LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*")
REG_RE = re.compile(r"^[rR]([0-7])$")


class AsmError(Exception):
    def __init__(self, lineno, msg):
        super().__init__(f"assembler: error: line {lineno}: {msg}")


def reg(tok, lineno):
    m = REG_RE.match(tok)
    if not m:
        raise AsmError(lineno, f"expected register r0..r7, got '{tok}'")
    return int(m.group(1))


def num(tok, lineno, lo, hi, what):
    try:
        v = int(tok, 0)
    except ValueError:
        raise AsmError(lineno, f"bad number '{tok}' for {what}")
    if not lo <= v <= hi:
        raise AsmError(lineno, f"{what} {v} out of range {lo}..{hi}")
    return v


def strip_comment(line):
    for c in (";", "#", "--"):
        line = line.split(c)[0]
    return line


def tokenize(text):
    """First pass: returns (items, labels). items = (lineno, mnem, [operands])."""
    items, labels = [], {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        code = strip_comment(raw).strip()
        if not code:
            continue
        while True:                              # peel leading "label:" prefixes
            m = LABEL_RE.match(code)
            if not m:
                break
            name = m.group(1).lower()
            if name in labels:
                raise AsmError(lineno, f"duplicate label '{name}'")
            labels[name] = len(items)
            code = code[m.end():].strip()
        if not code:
            continue
        parts = code.replace(",", " ").split()
        items.append((lineno, parts[0].lower(), parts[1:]))
    return items, labels


def target_addr(tok, labels, lineno):
    """Branch/jump operand: label or numeric address."""
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", tok):
        name = tok.lower()
        if name not in labels:
            raise AsmError(lineno, f"undefined label '{tok}'")
        return labels[name]
    return num(tok, lineno, 0, 255, "address")


def assemble(text):
    """Second pass: returns the list of 16-bit instruction words."""
    items, labels = tokenize(text)
    words = []
    for addr, (lineno, mnem, ops) in enumerate(items):
        if mnem in R3:
            if len(ops) != 3:
                raise AsmError(lineno, f"{mnem} needs 3 operands: {mnem} rd, rs, rt")
            rd, rs, rt = reg(ops[0], lineno), reg(ops[1], lineno), reg(ops[2], lineno)
            word = (R3[mnem] << 12) | (rd << 9) | (rs << 6) | (rt << 3)
        elif mnem in R2:
            if len(ops) != 2:
                raise AsmError(lineno, f"{mnem} needs 2 operands: {mnem} rd, rs")
            rd, rs = reg(ops[0], lineno), reg(ops[1], lineno)
            word = (R2[mnem] << 12) | (rd << 9) | (rs << 6)
        elif mnem in RI:
            if len(ops) != 2:
                raise AsmError(lineno, "loadi needs 2 operands: loadi rd, imm")
            rd = reg(ops[0], lineno)
            imm = num(ops[1], lineno, -32, 31, "loadi immediate")
            word = (RI[mnem] << 12) | (rd << 9) | (imm & 0x3F)
        elif mnem in BR:
            if len(ops) != 3:
                raise AsmError(lineno, f"{mnem} needs 3 operands: {mnem} rs, rt, label")
            rs, rt = reg(ops[0], lineno), reg(ops[1], lineno)
            if re.fullmatch(r"-?\d+", ops[2]):       # raw numeric offset allowed
                off = num(ops[2], lineno, -32, 31, "branch offset")
            else:
                dst = target_addr(ops[2], labels, lineno)
                off = dst - (addr + 1)
                if not -32 <= off <= 31:
                    raise AsmError(lineno, f"branch to '{ops[2]}' out of range "
                                           f"(offset {off}, allowed -32..31)")
            word = (BR[mnem] << 12) | (rt << 9) | (rs << 6) | (off & 0x3F)
        elif mnem == "jmp":
            if len(ops) != 1:
                raise AsmError(lineno, "jmp needs 1 operand: jmp label")
            dst = target_addr(ops[0], labels, lineno)
            word = (OP_JMP << 12) | dst
        elif mnem == "halt":
            if ops:
                raise AsmError(lineno, "halt takes no operands")
            word = OP_HALT << 12
        else:
            raise AsmError(lineno, f"unknown instruction '{mnem}'")
        words.append(word)
    if not words:
        raise AsmError(1, "program is empty")
    return words


def to_vhdl(words, asm_path):
    base = os.path.splitext(os.path.basename(asm_path))[0]
    pkg = re.sub(r"[^a-z0-9_]", "", base.lower()) + "_rom"
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
        chunk = ", ".join(f'x"{w:04X}"' for w in words[i:i + 4])
        tail = "," if i + 4 < len(words) else ""
        lines.append(f"    {chunk}{tail}")
    lines += [");", f"end package {pkg};", ""]
    return "\n".join(lines), pkg


def main():
    ap = argparse.ArgumentParser(description="MiniCPU-8 assembler")
    ap.add_argument("input", help=".asm source file")
    ap.add_argument("--vhdl", metavar="FILE", help="write VHDL ROM package")
    ap.add_argument("--hex", metavar="FILE", help="write hex word list")
    args = ap.parse_args()

    try:
        with open(args.input) as f:
            text = f.read()
        words = assemble(text)
    except AsmError as e:
        sys.exit(str(e))
    except OSError as e:
        sys.exit(f"assembler: error: cannot read {args.input}: {e}")

    hex_lines = [f"{w:04X}" for w in words]
    if args.vhdl:
        src, _ = to_vhdl(words, args.input)
        with open(args.vhdl, "w") as f:
            f.write(src)
        print(f"{args.input}: {len(words)} words -> {args.vhdl}", file=sys.stderr)
    if args.hex:
        with open(args.hex, "w") as f:
            f.write("\n".join(hex_lines) + "\n")
        print(f"{args.input}: {len(words)} words -> {args.hex}", file=sys.stderr)
    if not args.vhdl and not args.hex:
        print("\n".join(hex_lines))


if __name__ == "__main__":
    main()
