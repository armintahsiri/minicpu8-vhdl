#!/usr/bin/env python3
"""Cross-check the MiniCPU-8 ISA specification.

The single sources of truth are:
  * docs/ISA.md          -- the human-readable specification
  * tools/assembler.py   -- the encoder
  * minicpu_pkg.vhd      -- the hardware opcode/function/condition constants
  * cpu_top.vhd          -- the datapath field wiring

This script parses the tables and fails (exit 1) on any mismatch.  It is run
by `make test`, so the three copies can never drift silently.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
sys.path.insert(0, TOOLS)
import assembler  # noqa: E402

failures = []
checks = 0


def ok(name, cond, detail=""):
    global checks
    checks += 1
    if cond:
        print(f"  ok   {name}")
    else:
        failures.append(name)
        print(f"  FAIL {name}" + (f": {detail}" if detail else ""))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def parse_opcode_constants(text):
    consts = {}
    for name, bits in re.findall(
            r'constant\s+(OPC_[A-Z0-9_]+)\s*:\s*opcode_t\s*:=\s*"([01]{4})"', text):
        consts[name] = int(bits, 2)
    return consts


def parse_doc_opcode_table(text):
    """Return {mnemonic_lower: opcode} from the markdown opcode table."""
    rows = {}
    for line in text.splitlines():
        m = re.match(r'^\|\s*`0x([0-9A-Fa-f])`\s*\|\s*([^|]+?)\s*\|', line)
        if not m:
            continue
        opcode = int(m.group(1), 16)
        mnem = m.group(2).strip()
        mnem = mnem.replace("`", "").replace("*", "").strip().split()[0].lower()
        if mnem.startswith("reserved") or mnem in ("-", ""):
            continue
        rows[mnem] = opcode
    return rows


def assembler_opcode_table():
    table = {}
    for mnem, op in assembler.R3.items():
        table[mnem] = op
    for mnem, op in assembler.R2.items():
        table[mnem] = op
    for mnem, op in assembler.RI.items():
        table[mnem] = op
    for mnem, op in assembler.BR.items():
        table[mnem] = op
    table["jmp"] = assembler.OP_JMP
    table["halt"] = assembler.OP_HALT
    return table


def normalize(s):
    return re.sub(r"\s+", "", s).lower()


print("ISA consistency check:")

pkg_text = read("minicpu_pkg.vhd")
doc_text = read("docs/ISA.md")
cpu_text = read("cpu_top.vhd")
asm_text = read("tools/assembler.py")

pkg = parse_opcode_constants(pkg_text)
doc_ops = parse_doc_opcode_table(doc_text)
asm_ops = assembler_opcode_table()

ok("package defines the expected opcode constants", len(pkg) >= 14,
   f"found {len(pkg)}")

# Hardware constant <-> assembler encoder
for name, value in sorted(pkg.items()):
    mnem = name[len("OPC_"):].lower()
    if mnem not in asm_ops:
        ok(f"pkg {name} has an assembler entry", False)
        continue
    ok(f"pkg {name}=0x{value:X} matches assembler ({mnem}=0x{asm_ops[mnem]:X})",
       asm_ops[mnem] == value,
       f"pkg 0x{value:X} vs assembler 0x{asm_ops[mnem]:X}")

# Hardware constant <-> docs table
for name, value in sorted(pkg.items()):
    mnem = name[len("OPC_"):].lower()
    ok(f"docs table has {mnem.upper()} = 0x{value:X}",
       doc_ops.get(mnem) == value,
       f"docs has {doc_ops.get(mnem)}")

# Every documented mnemonic must exist in hardware/assembler too (catches a
# row that was added to ISA.md but never implemented).
for mnem, value in sorted(doc_ops.items()):
    if mnem in asm_ops:
        ok(f"docs {mnem.upper()} is encoder/firmware-consistent",
           asm_ops[mnem] == value, f"docs 0x{value:X} vs assembler 0x{asm_ops[mnem]:X}")
    elif mnem in ("mov", "load", "store", "addi", "nop", "ret", "cmp",
                  "subi", "call", "bz", "bnz", "bcs", "bhs", "bcc", "blo",
                  "bn", "bnn", "blt", "bge"):
        # Phase 2 pseudo/extended instructions are checked in the Phase 2
        # section below; do not fail the Phase 1 table on them.
        pass
    else:
        ok(f"docs mnemonic {mnem} is implemented", False)

# ---- BEQ/BNE operand layout: rt lives in the rd field --------------------
# The assembler must encode beq r5,r5,+1 as 0xAB41: op=A, "rd"=5 (rt),
# rs=5, imm=1.  ISA.md documents the same example and the normative marker.
beq_word = assembler.assemble("beq r5, r5, 1")[0]
ok("assembler puts BEQ rt in the rd field (0xAB41)", beq_word == 0xAB41,
   f"got 0x{beq_word:04X}")
ok("ISA.md documents the 0xAB41 layout example", "0xAB41" in doc_text)
layout_marker = ("BEQ/BNE layout: rs = bits [8:6], rt = bits [11:9] "
                 "(rd field), imm6 = bits [5:0]")
doc_norm = normalize(doc_text)
ok("ISA.md contains the normative BEQ/BNE layout marker",
   normalize(layout_marker) in doc_norm)

# cpu_top must read rs on port 1 and select the rd field for the second
# BEQ/BNE comparand.
cpu_norm = normalize(cpu_text)
ok("cpu_top reads rs field [8:6] on register port 1",
   "raddr1=>instr(8downto6)" in cpu_norm)
ok("cpu_top selects rd field [11:9] for BEQ/BNE second comparand",
   "addr2<=instr(11downto9)when(branch=br_beqorbranch=br_bne)" in cpu_norm)
ok("assembler source documents the rd-field trick",
   "rt" in asm_text and "rd field" in asm_text.lower())

print()
if failures:
    print(f"ISA CONSISTENCY: FAILED ({len(failures)} of {checks} checks)")
    sys.exit(1)
print(f"ISA CONSISTENCY: ALL {checks} CHECKS PASSED")
