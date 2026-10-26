#!/usr/bin/env python3
"""Unit tests for tools/isa_sim.py. Run: python3 tools/test_isa_sim.py

Expected values are computed by hand from docs/ISA.md.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import isa_sim  # noqa: E402

failures = []
count = 0


def ok(name, cond, detail=""):
    global count
    count += 1
    if cond:
        print(f"  ok   {name}")
    else:
        failures.append(name)
        print(f"  FAIL {name}" + (f": {detail}" if detail else ""))


def run(text, max_cycles=100000, **kwargs):
    cpu, res = isa_sim.run_source(text, max_cycles=max_cycles, **kwargs)
    return cpu, res


def eq(name, got, exp):
    ok(name, got == exp, f"got {got!r}, expected {exp!r}")


print("isa_sim unit tests:")

# ---------------- ALU and flag reference ----------------
eq("sext6(0x1F)", isa_sim.sext6(0x1F), 31)
eq("sext6(0x20)", isa_sim.sext6(0x20), -32)
eq("sext6(0x3F)", isa_sim.sext6(0x3F), -1)
eq("ALU ADD 7F+01", isa_sim.alu(isa_sim.ALU_ADD, 0x7F, 1), (0x80, 0, 1, 0, 1))
eq("ALU ADD FF+01", isa_sim.alu(isa_sim.ALU_ADD, 0xFF, 1), (0x00, 1, 0, 1, 0))
eq("ALU SUB 03-05", isa_sim.alu(isa_sim.ALU_SUB, 3, 5), (0xFE, 0, 1, 0, 0))
eq("ALU SUB 05-03", isa_sim.alu(isa_sim.ALU_SUB, 5, 3), (0x02, 0, 0, 1, 0))
eq("ALU SUB 05-05", isa_sim.alu(isa_sim.ALU_SUB, 5, 5), (0x00, 1, 0, 1, 0))
eq("ALU SUB 80-01", isa_sim.alu(isa_sim.ALU_SUB, 0x80, 1), (0x7F, 0, 0, 1, 1))
eq("ALU AND clears C/V", isa_sim.alu(isa_sim.ALU_AND, 0xFF, 0x80), (0x80, 0, 1, 0, 0))
eq("ALU OR", isa_sim.alu(isa_sim.ALU_OR, 0x10, 0x01), (0x11, 0, 0, 0, 0))
eq("ALU XOR", isa_sim.alu(isa_sim.ALU_XOR, 0xF0, 0x5A), (0xAA, 0, 1, 0, 0))
eq("ALU NOT", isa_sim.alu(isa_sim.ALU_NOT, 0x00, 0x77), (0xFF, 0, 1, 0, 0))
eq("ALU SHL 7F", isa_sim.alu(isa_sim.ALU_SHL, 0x7F, 0), (0xFE, 0, 1, 0, 1))
eq("ALU SHL 80", isa_sim.alu(isa_sim.ALU_SHL, 0x80, 0), (0x00, 1, 0, 1, 1))
eq("ALU SHR 01", isa_sim.alu(isa_sim.ALU_SHR, 0x01, 0), (0x00, 1, 0, 1, 0))
eq("ALU PASS_B", isa_sim.alu(isa_sim.ALU_PASS_B, 0xFF, 0x42), (0x42, 0, 0, 0, 0))

# ---------------- Phase 1 programs ----------------
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "programs")
with open(os.path.join(base, "sum1to10.asm")) as f:
    cpu, _ = run(f.read())
eq("sum1to10 r1=55", cpu.regs[1], 55)
eq("sum1to10 i=11", cpu.regs[2], 11)
eq("sum1to10 pc", cpu.pc, 6)
eq("sum1to10 cycles", cpu.cycles, 33)
eq("sum1to10 halted", cpu.halted, True)

with open(os.path.join(base, "shift_branch.asm")) as f:
    cpu, _ = run(f.read())
eq("shift_branch regs", cpu.regs, [0, 3, 12, 6, 10, 13, 0, 0])
eq("shift_branch pc", cpu.pc, 9)
eq("shift_branch cycles", cpu.cycles, 8)
eq("shift_branch flags", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 0, 0, 0))

# ---------------- ALU instructions and flags ----------------
cpu, _ = run("loadi r1, 31\nshl r1,r1\nshl r1,r1\naddi r1,r1,3\naddi r1,r1,1\nhalt")
eq("ADD overflow r1=80", cpu.regs[1], 0x80)
eq("ADD overflow flags", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 1, 0, 1))

cpu, _ = run("loadi r1,3\nloadi r2,5\nsub r3,r1,r2\nhalt")
eq("SUB borrow r3=FE", cpu.regs[3], 0xFE)
eq("SUB borrow flags", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 1, 0, 0))

cpu, _ = run("loadi r1,5\nloadi r2,3\nsub r3,r1,r2\nand r4,r1,r2\nhalt")
eq("logic clears C after SUB C=1", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 0, 0, 0))

cpu, _ = run("loadi r1,31\nshl r1,r1\nshl r1,r1\naddi r1,r1,3\nshl r1,r1\nhalt")
eq("SHL 7F -> FE and V=1", cpu.regs[1], 0xFE)
eq("SHL 7F flags", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 1, 0, 1))

cpu, _ = run("loadi r1,-1\nshr r2,r1\nhalt")
eq("SHR FF -> 7F", cpu.regs[2], 0x7F)
eq("SHR flags", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 0, 1, 0))

cpu, _ = run("loadi r1,-32\nnot r2,r1\nhalt")
eq("LOADI -32 sext", cpu.regs[1], 0xE0)
eq("NOT E0 -> 1F", cpu.regs[2], 0x1F)
eq("NOT flags", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 0, 0, 0))

# MOV is a pseudo-instruction for ADD, so it now writes flags.
cpu, _ = run("loadi r1,1\nsub r2,r0,r1\nloadi r3,3\nmov r1,r3\nhalt")
eq("MOV result", cpu.regs[1], 3)
eq("MOV writes flags (ADD semantics)", (cpu.z, cpu.n, cpu.c, cpu.v), (0, 0, 0, 0))

# ---------------- LOAD / STORE / RAM init ----------------
prog = """
.data 16, 5, 0xFE, 0x7F
        loadi r1, 16
        load  r2, [r1+0]
        load  r3, [r1+1]
        store r3, [r1+2]
        load  r4, [r1+2]
        halt
"""
cpu, _ = run(prog)
eq("LOAD r2", cpu.regs[2], 5)
eq("LOAD r3", cpu.regs[3], 0xFE)
eq("STORE then LOAD r4", cpu.regs[4], 0xFE)
eq("RAM cell overwritten", cpu.ram[18], 0xFE)
eq("RAM init elsewhere", cpu.ram[17], 0xFE)

# address wrap: 0xFF + 2 = 0x01 and 0xFF + 3 = 0x02
prog = """
.data 1, 0x42
        loadi r1, -1
        load  r2, [r1+2]
        loadi r3, 7
        store r3, [r1+3]
        halt
"""
cpu, _ = run(prog)
eq("LOAD address wrap to 0x01", cpu.regs[2], 0x42)
eq("STORE address wrap to 0x02", cpu.ram[2], 7)

# ---------------- R0 hardwired ----------------
cpu, _ = run("loadi r1,9\nmov r0,r1\naddi r0,r0,1\nstore r0,[r0+3]\nhalt")
eq("R0 stays zero after MOV/ADDI", cpu.regs[0], 0)
eq("STORE from R0 writes zero", cpu.ram[3], 0)
cpu, _ = run(".data 4, 0x77\nload r0,[r0+4]\nhalt")
eq("LOAD to R0 ignored", cpu.regs[0], 0)

# ---------------- CMP and flag branches ----------------
prog = """
        loadi r1, 5
        loadi r2, 5
        cmp   r1, r2
        bz    eq
        loadi r3, 1
        halt
eq:     loadi r3, 2
        halt
"""
cpu, _ = run(prog)
eq("CMP+BZ taken", cpu.regs[3], 2)

prog = """
        loadi r1, 5
        loadi r2, 6
        cmp   r1, r2
        bnz   ne
        loadi r3, 1
        halt
ne:     loadi r3, 2
        halt
"""
cpu, _ = run(prog)
eq("CMP+BNZ taken", cpu.regs[3], 2)

# unsigned vs signed: 0xFE (-2) vs 0x01
prog = """
        loadi r1, -2
        loadi r2, 1
        cmp   r1, r2
        blo   u_less
        bcs   u_ge
        loadi r3, 0x0E
        jmp   s
u_less: loadi r3, 0x11
        jmp   s
u_ge:   loadi r3, 0x12
s:      cmp   r1, r2
        blt   s_less
        bge   s_ge
        loadi r4, 0x13
        jmp   done
s_less: loadi r4, 0x14
        jmp   done
s_ge:   loadi r4, 0x15
done:   halt
"""
cpu, _ = run(prog)
eq("unsigned BCS taken / BLO not", cpu.regs[3], 0x12)
eq("signed BLT taken / BGE not", cpu.regs[4], 0x14)

# BN / BNN and BGE
prog = """
        loadi r1, 0
        loadi r2, 1
        sub   r3, r1, r2     ; 0xFF, N=1
        bn    neg
        loadi r4, 1
        halt
neg:    loadi r4, 2
        halt
"""
cpu, _ = run(prog)
eq("BN taken", cpu.regs[4], 2)

# ---------------- HALT, fall-off, JMP 0xFF ----------------
cpu, _ = run("loadi r1,5\nhalt\nloadi r2,9")
eq("HALT stops before following instruction", cpu.regs[2], 0)
eq("HALT pc", cpu.pc, 1)
eq("HALT cycles", cpu.cycles, 1)

cpu, _ = run("loadi r1,5")
eq("fall off end into HALT fill", (cpu.pc, cpu.halted, cpu.cycles), (1, True, 1))
eq("fall off end register", cpu.regs[1], 5)

cpu, _ = run("jmp 0xFF")
eq("JMP 0xFF executes HALT at 0xFF", (cpu.pc, cpu.halted, cpu.cycles), (255, True, 1))

# ---------------- PC wrap ----------------
prog = """
        jmp   0xFD
        loadi r2, 31
        halt
        .org 0xFD
        loadi r1, 1
        beq   r0, r0, 2
"""
cpu, _ = run(prog)
eq("forward BEQ wrap lands at 0x01", cpu.pc, 2)
eq("forward BEQ wrap ran marker", cpu.regs[2], 31)

prog = """
        beq   r0, r0, -2
        halt
        loadi r3, 7
        halt
        .org 0xFF
        jmp   0x02
"""
cpu, _ = run(prog)
eq("backward BEQ wrap lands at 0xFF", cpu.pc, 3)
eq("backward BEQ wrap ran marker", cpu.regs[3], 7)

# ---------------- CALL / RET ----------------
prog = """
        loadi r1, 3
        call  sub
        addi  r2, r2, 1
        call  sub
        halt
sub:    add   r2, r2, r1
        ret
"""
cpu, _ = run(prog)
eq("CALL/RET called twice", cpu.regs[2], 7)
eq("CALL/RET halts", cpu.halted, True)

# nested call: outer saves R7 to RAM[20], inner overwrites R7
prog = """
main:   call  outer
        halt
outer:  store r7, [r0+20]
        call  inner
        load  r7, [r0+20]
        ret
inner:  loadi r1, 7
        ret
"""
cpu, _ = run(prog)
eq("nested CALL/RET returns to main", cpu.pc, 1)
eq("nested CALL/RET ran inner", cpu.regs[1], 7)
eq("nested CALL/RET saved link in RAM[20]", cpu.ram[20], 1)

# direct RET from a value loaded into R7
prog = """
        loadi r7, 4
        ret
        halt
        .org 4
        loadi r1, 9
        halt
"""
cpu, _ = run(prog)
eq("RET loads PC from R7", cpu.pc, 5)
eq("RET target ran", cpu.regs[1], 9)

# ---------------- flags untouched by non-flag instructions ----------------
prog = """
.data 16, 0x5A
        loadi r1, 1
        sub   r2, r0, r1    ; flags N=1, C=0, Z=0, V=0
        loadi r3, 5
        load  r4, [r0+16]
        store r4, [r0+17]
        jmp   skip
skip:   call  nothing
        halt
nothing: ret
"""
cpu, _ = run(prog)
eq("LOAD/STORE/JMP/CALL/RET preserve flags",
   (cpu.z, cpu.n, cpu.c, cpu.v), (0, 1, 0, 0))

# ---------------- timeout ----------------
cpu, _ = run("loop: jmp loop", max_cycles=10)
eq("runaway loop times out", (cpu.halted, cpu.timeout, cpu.cycles), (False, True, 10))

# ---------------- MMIO: UART / GPIO / cycle counter ----------------
io_prog = """
        loadi r1, UART_STATUS
        loadi r2, UART_TX
        loadi r3, 0x15
        store r3, [r2+0]      ; accepted
        load  r4, [r1+0]      ; busy
        store r3, [r2+0]      ; ignored while busy
        loadi r5, 0x16
        store r5, [r2+0]      ; ignored while busy
        load  r6, [r0+GPIO_IN]
        load  r7, [r0+GPIO_OUT]
        halt
"""
cpu, _ = run(io_prog, gpio_in=0xA5, clks_per_bit=4)
eq("UART accepted byte captured", cpu.uart_out, [0x15])
eq("UART status busy after store", cpu.regs[4], 1)
eq("UART write-while-busy ignored", cpu.uart_out, [0x15])
eq("GPIO_IN parameter read", cpu.regs[6], 0xA5)
eq("GPIO_OUT initial zero", cpu.regs[7], 0x00)

# Hand-derived synchronizer table: a LOAD executing in cycle c observes the
# pin schedule from c-2. Initial/reset value is zero.
gpio_schedule = [(0, 0x10), (2, 0x20), (4, 0x40)]
gpio_latency_prog = """
        loadi r1, GPIO_IN
        load r2, [r1+0]   ; c=1 -> initial/reset value
        nop
        load r3, [r1+0]   ; c=3 -> schedule value at c=1
        load r4, [r1+0]   ; c=4 -> schedule value at c=2
        nop
        load r5, [r1+0]   ; c=6 -> schedule value at c=4
        halt
"""
cpu, _ = run(gpio_latency_prog, gpio_schedule=gpio_schedule)
eq("GPIO schedule latency c-2", cpu.regs[2:6], [0x00, 0x10, 0x20, 0x40])

gpio_prog = """
        loadi r1, 0x15
        store r1, [r0+GPIO_OUT]
        load  r2, [r0+GPIO_OUT]
        halt
"""
cpu, _ = run(gpio_prog)
eq("GPIO_OUT write/readback model", (cpu.gpio_out, cpu.regs[2]), (0x15, 0x15))

cycle_prog = """
        load r1, [r0+CYCLE_COUNT_LO]
        load r2, [r0+CYCLE_COUNT_LO]
        halt
"""
cpu, _ = run(cycle_prog)
eq("cycle counter low byte", (cpu.regs[1], cpu.regs[2]), (0, 1))

poll_prog = """
        loadi r1, UART_STATUS
        loadi r2, UART_TX
        loadi r3, 0x15
        store r3, [r2+0]
poll:   load  r4, [r1+0]
        cmp   r4, r0
        bnz   poll
        halt
"""
cpu, _ = run(poll_prog, clks_per_bit=4)
eq("UART busy polling terminates", (cpu.halted, cpu._uart_busy()), (True, 0))
ok("UART busy polling waited", cpu.cycles > 40, f"cycles={cpu.cycles}")

# ---------------- state is JSON serialisable ----------------
cpu, _ = run("loadi r1, 7\nhalt")
state = cpu.state()
ok("state JSON serialisable", json.loads(json.dumps(state)) == state)
eq("state keys", sorted(state),
   ["cycles", "flags", "gpio_in", "gpio_out", "halted", "pc", "ram", "regs",
    "timeout", "uart_busy", "uart_hex", "uart_out"])
eq("state ram length", len(state["ram"]), 256)

print()
if failures:
    print(f"ISA SIM TESTS: FAILED ({len(failures)} of {count} failures)")
    sys.exit(1)
print(f"ISA SIM TESTS: ALL {count} TESTS PASSED")
