#!/usr/bin/env python3
"""Unit tests for tools/assembler.py. Run: python3 tools/test_assembler.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assembler  # noqa: E402

failures = []


def ok(name, cond):
    if cond:
        print(f"  ok   {name}")
    else:
        failures.append(name)
        print(f"  FAIL {name}")


def asm(s):
    return assembler.assemble(s)


def raises(name, text, want_substr):
    try:
        asm(text)
    except assembler.AsmError as e:
        ok(name, want_substr in str(e))
        return
    ok(name, False)  # did not raise


print("assembler unit tests:")

# --- basic encodings (cross-checked against docs/ISA.md examples) ---
ok("add r1,r2,r3", asm("add r1, r2, r3") == [0x0298])
ok("sub r7,r6,r5", asm("sub r7, r6, r5") == [0x1FA8])
ok("and r1,r2,r3", asm("and r1, r2, r3") == [0x2298])
ok("or  r1,r2,r3", asm("or r1, r2, r3") == [0x3298])
ok("xor r4,r2,r3", asm("xor r4, r2, r3") == [0x5898])
ok("not r1,r2", asm("not r1, r2") == [0x4280])
ok("shl r2,r1", asm("shl r2, r1") == [0x6440])
ok("shr r3,r2", asm("shr r3, r2") == [0x7680])
ok("mov r3,r4 (rt=0)", asm("mov r3, r4") == [0x8700])
ok("loadi r1,5", asm("loadi r1, 5") == [0x9205])
ok("loadi r1,-1 (sext)", asm("loadi r1, -1") == [0x923F])
ok("loadi r1,0x0F hex", asm("loadi r1, 0x0F") == [0x920F])
ok("halt", asm("halt") == [0xD000])
ok("jmp 8 (absolute)", asm("jmp 8") == [0xC008])

# --- labels, case-insensitivity, comments ---
prog = """
start:              ; comment only
        LOADI r1, 5      # uppercase mnemonic
loop:   add r1, r1, r1   -- vhdl style comment
        BNE r1, r0, LOOP
        JMP Start
        Halt
"""
ok("label program", asm(prog) == [0x9205, 0x0248, 0xB07E, 0xC000, 0xD000])

# label alone on its line binds to the NEXT instruction (the halt at addr 1),
# so the beq at addr 2 gets offset 1 - (2+1) = -2
prog2 = """
        loadi r1, 1
end:
        halt
        beq r0, r0, end
"""
ok("forward label on own line", asm(prog2) == [0x9201, 0xD000, 0xA03E])

# numeric branch offsets pass through unchanged
ok("numeric branch offset", asm("beq r5, r5, 1") == [0xAB41])

# --- errors carry line numbers ---
raises("bad register", "add r1, r2, r8", "line 1")
raises("loadi too big", "loadi r1, 40", "line 1")
raises("loadi too small", "loadi r1, -33", "line 1")
raises("undefined label", "beq r1, r2, nowhere", "line 1: undefined label 'nowhere'")
raises("unknown mnemonic", "foo r1", "line 1: unknown instruction 'foo'")
raises("duplicate label", "a: halt\na: halt", "line 2: duplicate label")
raises("wrong arity", "add r1, r2", "line 1: add needs 3 operands")
raises("halt with operand", "halt r1", "line 1")
raises("empty program", "   ; nothing here\n", "program is empty")
raises("branch out of range", "nop1:\n" + " halt\n" * 40 + " beq r0, r0, nop1",
       "out of range")

# --- VHDL emitter ---
src, pkg = assembler.to_vhdl([0x9200, 0xD000], "sum1to10.asm")
ok("vhdl package name", pkg == "sum1to10_rom")
ok("vhdl words emitted", 'x"9200"' in src and 'x"D000"' in src)

# --- real programs match the hand-verified encodings used in cpu_tb ---
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "programs")
with open(os.path.join(base, "sum1to10.asm")) as f:
    ok("sum1to10.asm encodes", asm(f.read()) ==
       [0x9200, 0x9401, 0x960B, 0x9801, 0x0250, 0x04A0, 0xB6BD, 0xD000])
with open(os.path.join(base, "shift_branch.asm")) as f:
    ok("shift_branch.asm encodes", asm(f.read()) ==
       [0x9203, 0x6440, 0x6480, 0x7680, 0x5898, 0x0B08, 0x9C00, 0xAB41, 0x9C3F, 0xD000])

print()
if failures:
    print(f"ASSEMBLER TESTS: FAILED ({len(failures)} failures)")
    sys.exit(1)
print("ASSEMBLER TESTS: ALL TESTS PASSED")
