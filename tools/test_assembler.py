#!/usr/bin/env python3
"""Unit tests for tools/assembler.py (ISA v2). Run: python3 tools/test_assembler.py

Every expected encoding below is computed by hand from docs/ISA.md, not by
calling the assembler.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assembler  # noqa: E402

failures = []
count = 0


def ok(name, cond):
    global count
    count += 1
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


def raises_full(name, text, want_substr):
    try:
        assembler.assemble_with_data(text)
    except assembler.AsmError as e:
        ok(name, want_substr in str(e))
        return
    ok(name, False)


print("assembler unit tests (ISA v2):")

# --- Phase 1 encodings that do not change ---
ok("add r1,r2,r3", asm("add r1, r2, r3") == [0x0298])
ok("sub r7,r6,r5", asm("sub r7, r6, r5") == [0x1FA8])
ok("and r1,r2,r3", asm("and r1, r2, r3") == [0x2298])
ok("or  r1,r2,r3", asm("or r1, r2, r3") == [0x3298])
ok("xor r4,r2,r3", asm("xor r4, r2, r3") == [0x5898])
ok("not r1,r2", asm("not r1, r2") == [0x4280])
ok("shl r2,r1", asm("shl r2, r1") == [0x6440])
ok("shr r3,r2", asm("shr r3, r2") == [0x7680])
ok("loadi r1,5", asm("loadi r1, 5") == [0x9205])
ok("loadi r1,-1 (sext)", asm("loadi r1, -1") == [0x923F])
ok("loadi r1,0x0F hex", asm("loadi r1, 0x0F") == [0x920F])
ok("loadi r1,-32 min", asm("loadi r1, -32") == [0x9220])
ok("loadi r1,31 max", asm("loadi r1, 31") == [0x921F])
ok("jmp 8 (absolute)", asm("jmp 8") == [0xC008])

# --- changed Phase 1 encodings: MOV is ADD rd,rs,R0; HALT is EXT func 1 ---
ok("mov r3,r4 = add r3,r4,r0", asm("mov r3, r4") == [0x0700])
ok("halt = 0xF001", asm("halt") == [0xF001])
ok("nop = 0xF000", asm("nop") == [0xF000])
ok("ret = 0xF002", asm("ret") == [0xF002])

# --- ADDI / SUBI ---
ok("addi r1,r2,-1", asm("addi r1, r2, -1") == [0xE2BF])
ok("addi r7,r6,5", asm("addi r7, r6, 5") == [0xEF85])
ok("addi r1,r2,-32", asm("addi r1, r2, -32") == [0xE2A0])
ok("addi r1,r2,31", asm("addi r1, r2, 31") == [0xE29F])
ok("subi r1,r2,5", asm("subi r1, r2, 5") == [0xE2BB])       # addi -5 = 0x3B
ok("subi r1,r2,-31", asm("subi r1, r2, -31") == [0xE29F])   # addi +31
ok("subi r1,r2,32", asm("subi r1, r2, 32") == [0xE2A0])     # addi -32
ok("subi r1,r2,0", asm("subi r1, r2, 0") == [0xE280])

# --- LOAD / STORE (address = rs + sext(imm6), mod 256) ---
ok("load r3,[r4+7]", asm("load r3, [r4+7]") == [0x8707])
ok("load r1,[r2-1]", asm("load r1, [r2-1]") == [0x82BF])
ok("load r0,[r0]", asm("load r0, [r0]") == [0x8000])
ok("load spaces [r2 + 4]", asm("load r1, [ r2 + 4 ]") == [0x8284])
# --- MMIO symbols (Phase 3): addresses encoded as signed 6-bit offsets ---
ok("loadi r1, UART_TX", asm("loadi r1, UART_TX") == [0x9230])
ok("loadi r1, UART_STATUS", asm("loadi r1, UART_STATUS") == [0x9231])
ok("loadi r1, GPIO_OUT", asm("loadi r1, GPIO_OUT") == [0x9232])
ok("loadi r1, GPIO_IN", asm("loadi r1, GPIO_IN") == [0x9233])
ok("loadi r1, CYCLE_COUNT_LO", asm("loadi r1, CYCLE_COUNT_LO") == [0x9234])
ok("load r2,[r0+UART_STATUS]", asm("load r2, [r0+UART_STATUS]") == [0x8431])
ok("store r3,[r0+GPIO_OUT]", asm("store r3, [r0+GPIO_OUT]") == [0xD632])
ok("load r1,[r2+UART_TX] (offset -16)", asm("load r1, [r2+UART_TX]") == [0x82B0])
ok("store r5,[r6+0]", asm("store r5, [r6+0]") == [0xDB80])
ok("store r7,[r1-32]", asm("store r7, [r1-32]") == [0xDE60])
ok("store r0,[r0+31]", asm("store r0, [r0+31]") == [0xD01F])

# --- CMP / extended group ---
ok("cmp r1,r2", asm("cmp r1, r2") == [0xF053])
ok("cmp r7,r0", asm("cmp r7, r0") == [0xF1C3])

# --- jump group: every condition, both aliases, CALL ---
ok("jmp 0x80", asm("jmp 0x80") == [0xC080])
ok("bz 0x10", asm("bz 0x10") == [0xC110])
ok("bnz 0x20", asm("bnz 0x20") == [0xC220])
ok("bcs 0x30", asm("bcs 0x30") == [0xC330])
ok("bhs 0x30 alias", asm("bhs 0x30") == [0xC330])
ok("bcc 0x40", asm("bcc 0x40") == [0xC440])
ok("blo 0x40 alias", asm("blo 0x40") == [0xC440])
ok("bn 0x50", asm("bn 0x50") == [0xC550])
ok("bnn 0x60", asm("bnn 0x60") == [0xC660])
ok("blt 0x70", asm("blt 0x70") == [0xC770])
ok("bge 0x80", asm("bge 0x80") == [0xC880])
ok("call 0x90", asm("call 0x90") == [0xCF90])

# --- labels, case-insensitivity, comments ---
prog = """
start:              ; comment only
        LOADI r1, 5      # uppercase mnemonic
loop:   add r1, r1, r1   -- vhdl style comment
        BNE r1, r0, LOOP
        JMP Start
        Halt
"""
# add r1,r1,r1 = 0x0248; bne r1,r0,loop: loop=1, branch at 2 -> -2 = 0xB07E
ok("label program", asm(prog) == [0x9205, 0x0248, 0xB07E, 0xC000, 0xF001])

# label alone binds to the next instruction (halt at addr 1), so beq at addr 2
# gets offset 1 - (2+1) = -2
prog2 = """
        loadi r1, 1
end:
        halt
        beq r0, r0, end
"""
ok("forward label on own line", asm(prog2) == [0x9201, 0xF001, 0xA03E])

# numeric branch offsets pass through unchanged
ok("numeric branch offset", asm("beq r5, r5, 1") == [0xAB41])

# absolute label resolution + .org NOP fill
prog3 = """
start:  loadi r1, 1
        bz    done
        nop
        .org  3
done:   halt
"""
ok(".org fills with NOP and resolves absolute label",
   asm(prog3) == [0x9201, 0xC103, 0xF000, 0xF001])

prog4 = """
main:   call sub
        halt
        nop
        .org 3
sub:    ret
"""
ok("call label + ret", asm(prog4) == [0xCF03, 0xF001, 0xF000, 0xF002])

# --- .data / RAM initialisation ---
src, pkg = assembler.to_vhdl(
    assembler.assemble_with_data(".data 8, 0xAA, -1, 255\nmain: halt"),
    "array_sum.asm")
ok("vhdl rom package name", pkg == "array_sum_rom")
ok("vhdl ram package emitted", "package array_sum_ram is" in src)
ok("vhdl ram INIT emitted", "constant INIT : ram_init_t" in src)
ok("vhdl ram values emitted", '8 => x"AA"' in src and '9 => x"FF"' in src
   and '10 => x"FF"' in src)
res = assembler.assemble_with_data(".data 8, 1, 2, 3\nmain: nop")
ok("data ram length", len(res.ram) == 11)
ok("data ram contents", res.ram[8:11] == [1, 2, 3])
ok("data ram zero fill", res.ram[0:8] == [0] * 8)
res2 = assembler.assemble_with_data(".data 0, 0x12\n.data 2, 0x34\nmain: nop")
ok("multiple .data directives", res2.ram == [0x12, 0, 0x34])
res3 = assembler.assemble_with_data("nop")
ok("no data -> default one zero byte", assembler.to_vhdl(res3, "x.asm")[0].count('x"00"') >= 1)
res4 = assembler.assemble_with_data(".data 0xEF, 0xAA\nmain: nop")
ok("data may use last RAM cell 0xEF", len(res4.ram) == 240 and res4.ram[0xEF] == 0xAA)

# --- Phase 1 program encodings (regenerated with v2 HALT) ---
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "programs")
with open(os.path.join(base, "sum1to10.asm")) as f:
    ok("sum1to10.asm encodes (ADDI loop)",
       asm(f.read()) == [0x9200, 0x9401, 0x960B, 0x0250, 0xE481, 0xB6BD, 0xF001])
with open(os.path.join(base, "shift_branch.asm")) as f:
    ok("shift_branch.asm encodes",
       asm(f.read()) == [0x9203, 0x6440, 0x6480, 0x7680, 0x5898, 0x0B08,
                         0x9C00, 0xAB41, 0x9C3F, 0xF001])

# --- errors carry line numbers and clear messages ---
raises("bad register", "add r1, r2, r8", "line 1")
raises("loadi too big", "loadi r1, 32", "line 1")
raises("loadi too small", "loadi r1, -33", "line 1")
raises("addi too big", "addi r1, r2, 32", "line 1: addi immediate 32 out of range")
raises("subi too small", "subi r1, r2, -32", "line 1: subi immediate -32 out of range")
raises("subi too big", "subi r1, r2, 33", "line 1: subi immediate 33 out of range")
raises("load offset out of range", "load r1, [r2+32]", "memory offset 32 out of range")
raises("store offset out of range", "store r1, [r2-33]", "memory offset -33 out of range")
raises("bad memory operand", "load r1, r2", "expected memory operand")
raises("bad memory base", "store r1, [r8+0]", "line 1")
raises("bad register in store", "store r8, [r1+0]", "line 1")
raises("undefined branch label", "beq r1, r2, nowhere", "line 1: undefined label 'nowhere'")
raises("undefined absolute label", "call nowhere", "line 1: undefined label 'nowhere'")
raises("unknown instruction", "foo r1", "line 1: unknown instruction 'foo'")
raises("unknown directive", ".foo 1", "line 1: unknown directive '.foo'")
raises("duplicate label", "a: halt\na: halt", "line 2: duplicate label")
raises("wrong arity add", "add r1, r2", "line 1: add needs 3 operands")
raises("wrong arity addi", "addi r1, r2", "line 1: addi needs 3 operands")
raises("wrong arity cmp", "cmp r1", "line 1: cmp needs 2 operands")
raises("wrong arity load", "load r1", "line 1: load needs 2 operands")
raises("wrong arity store", "store r1", "line 1: store needs 2 operands")
raises("wrong arity jmp", "jmp 1, 2", "line 1: jmp needs 1 operand")
raises("halt with operand", "halt r1", "line 1")
raises("ret with operand", "ret r1", "line 1")
raises("empty operand", "add r1,,r2", "line 1: empty operand")
raises("empty program", "   ; nothing here\n", "program is empty")
raises("data only is empty program", ".data 0, 1\n", "program is empty")
raises("branch out of range", "nop1:\n" + " halt\n" * 40 + " beq r0, r0, nop1",
       "out of range")
raises("absolute target out of range", "jmp 256", "jump target 256 out of range 0..255")
raises("call target out of range", "call 0x100", "jump target 256 out of range 0..255")
raises("org out of range", ".org 256", ".org address 256 out of range")
raises("org backwards", "nop\nnop\n.org 1", "line 3: .org cannot move backwards")
raises("org without address", ".org", "line 1")
raises("data without value", ".data 0", "line 1: .data needs an address")
raises("data byte out of range", ".data 0, 300", ".data byte 300 out of range")
raises("data runs into I/O region", ".data 0xEF, 1, 2", "runs into the I/O region")
raises("data base in I/O region", ".data 0xF0, 1", ".data address 240 out of range 0..239")
raises("I/O symbol as jump target", "jmp UART_TX", "not a jump target")
raises("I/O symbol as arithmetic immediate", "addi r1, r2, UART_TX",
       "not an arithmetic immediate")
raises("I/O symbol as label", "uart_tx: halt", "reserved I/O symbol")
raises("unknown symbol in loadi", "loadi r1, BOGUS", "unknown symbol 'BOGUS'")
raises("I/O symbol in .data value", ".data 0, UART_TX", "bad number 'UART_TX'")
raises("data overlap", "nop\n.data 1, 1\n.data 1, 2", "data address 1 already initialized")
raises("data bad number", ".data 0, xyz", "bad number 'xyz'")
raises("program exceeds 256", "nop\n.org 255\nnop\nnop", "program exceeds 256")

# --- VHDL emitter basics ---
src, pkg = assembler.to_vhdl([0x9200, 0xF001], "sum1to10.asm")
ok("vhdl package name (legacy call)", pkg == "sum1to10_rom")
ok("vhdl words emitted (legacy call)", 'x"9200"' in src and 'x"F001"' in src)

print()
if failures:
    print(f"ASSEMBLER TESTS: FAILED ({len(failures)} of {count} failures)")
    sys.exit(1)
print(f"ASSEMBLER TESTS: ALL {count} TESTS PASSED")
