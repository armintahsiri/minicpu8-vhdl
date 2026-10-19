#!/usr/bin/env python3
"""MiniCPU-8 ISA v2 golden model (Python 3).

This is a small instruction-set simulator used as the reference for the VHDL
CPU.  It implements docs/ISA.md exactly: sign-extended immediates, modulo-256
addressing, the ARM-style C=1-means-no-borrow SUB convention, CMP, flag-based
conditions, absolute jump-group targets, CALL/RET with the R7 link, LOAD/STORE
with 256-byte RAM, HALT, and R0 hardwired to zero.

Usage:
  python3 tools/isa_sim.py PROGRAM.asm [--json] [--ram] [--max-cycles N]

In JSON mode the final state is printed as one object; tools/fuzz.py uses that
as the golden state.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assembler  # noqa: E402

HALT_WORD = 0xF001
NOP_WORD = 0xF000

# ALU op codes mirror minicpu_pkg.alu_op_t ordering.
ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_NOT, ALU_PASS_B, ALU_XOR, ALU_SHL, ALU_SHR = range(9)


def sext6(x):
    x &= 0x3F
    return x - 64 if x & 0x20 else x


def sgn8(x):
    x &= 0xFF
    return x - 256 if x & 0x80 else x


def alu(op, a, b):
    """Return (result, Z, N, C, V) exactly like alu.vhd."""
    a &= 0xFF
    b &= 0xFF
    cf = vf = 0
    if op == ALU_ADD:
        full = a + b
        res = full & 0xFF
        cf = 1 if full > 0xFF else 0
        vf = 1 if ((a ^ res) & (b ^ res) & 0x80) else 0
    elif op == ALU_SUB:
        full = a - b
        res = full & 0xFF
        cf = 1 if a >= b else 0                 # C=1 means no borrow
        vf = 1 if ((a ^ b) & (a ^ res) & 0x80) else 0
    elif op == ALU_AND:
        res = a & b
    elif op == ALU_OR:
        res = a | b
    elif op == ALU_XOR:
        res = a ^ b
    elif op == ALU_NOT:
        res = (~a) & 0xFF
    elif op == ALU_SHL:
        res = (a << 1) & 0xFF
        cf = (a >> 7) & 1
        vf = ((a >> 7) ^ (res >> 7)) & 1
    elif op == ALU_SHR:
        res = a >> 1
        cf = a & 1
        vf = 0
    elif op == ALU_PASS_B:
        res = b
    else:
        raise ValueError(f"bad ALU op {op}")
    zf = 1 if (res & 0xFF) == 0 else 0
    nf = (res >> 7) & 1
    return res & 0xFF, zf, nf, cf, vf


class MiniCPU8:
    def __init__(self, words, ram=None, max_cycles=100000):
        if len(words) > 256:
            raise ValueError("program exceeds 256 words")
        self.rom = [HALT_WORD] * 256
        for i, w in enumerate(words):
            self.rom[i] = w & 0xFFFF
        self.ram = [0] * 256
        if ram:
            if len(ram) > 256:
                raise ValueError("RAM init exceeds 256 bytes")
            for i, b in enumerate(ram):
                self.ram[i] = b & 0xFF
        self.regs = [0] * 8
        self.z = self.n = self.c = self.v = 0
        self.pc = 0
        self.halted = False
        self.timeout = False
        self.cycles = 0
        self.max_cycles = max_cycles
        self.trace = []

    # -- helpers ---------------------------------------------------------
    def _wr(self, r, value):
        if r != 0:                       # R0 is hardwired to zero
            self.regs[r] = value & 0xFF

    def _flags(self, z, n, c, v):
        self.z, self.n, self.c, self.v = z, n, c, v

    def _addr(self, rs, imm6):
        return (self.regs[rs] + sext6(imm6)) & 0xFF

    def _is_halt(self, word):
        return ((word >> 12) & 0xF) == 0xF and (word & 0x7) == 0x1

    def _cond(self, code):
        if code == 0x0:
            return True                       # JMP / CALL
        if code == 0x1:
            return self.z == 1                # BZ
        if code == 0x2:
            return self.z == 0                # BNZ
        if code == 0x3:
            return self.c == 1                # BCS/BHS, unsigned >=
        if code == 0x4:
            return self.c == 0                # BCC/BLO, unsigned <
        if code == 0x5:
            return self.n == 1                # BN
        if code == 0x6:
            return self.n == 0                # BNN
        if code == 0x7:
            return (self.n ^ self.v) == 1     # BLT, signed <
        if code == 0x8:
            return (self.n ^ self.v) == 0     # BGE, signed >=
        return False                          # 0x9..0xE reserved -> NOP

    # -- execution -------------------------------------------------------
    def step(self):
        """Execute one non-HALT instruction.  HALT is detected by run()."""
        word = self.rom[self.pc]
        op = (word >> 12) & 0xF
        rd = (word >> 9) & 0x7
        rs = (word >> 6) & 0x7
        rt = (word >> 3) & 0x7
        imm = word & 0x3F
        func = word & 0x7
        cond = (word >> 8) & 0xF
        target = word & 0xFF

        self.trace.append((self.pc, word))
        next_pc = (self.pc + 1) & 0xFF

        if op <= 0x7:
            aluop = [ALU_ADD, ALU_SUB, ALU_AND, ALU_OR,
                     ALU_NOT, ALU_XOR, ALU_SHL, ALU_SHR][op]
            res, z, n, c, v = alu(aluop, self.regs[rs], self.regs[rt])
            self._wr(rd, res)
            self._flags(z, n, c, v)
        elif op == 0x8:                    # LOAD
            self._wr(rd, self.ram[self._addr(rs, imm)])
        elif op == 0x9:                    # LOADI
            self._wr(rd, sext6(imm) & 0xFF)
        elif op == 0xA:                    # BEQ (register comparator)
            # BEQ/BNE put the second comparand (rt) in the rd field.
            if self.regs[rs] == self.regs[rd]:
                next_pc = (self.pc + 1 + sext6(imm)) & 0xFF
        elif op == 0xB:                    # BNE
            if self.regs[rs] != self.regs[rd]:
                next_pc = (self.pc + 1 + sext6(imm)) & 0xFF
        elif op == 0xC:                    # jump group
            if cond == 0xF:                # CALL
                self._wr(7, next_pc)
                next_pc = target
            elif cond <= 0x8:
                if self._cond(cond):
                    next_pc = target
            # cond 0x9..0xE reserved -> fall through (NOP)
        elif op == 0xD:                    # STORE (data register in rd field)
            self.ram[self._addr(rs, imm)] = self.regs[rd]
        elif op == 0xE:                    # ADDI
            res, z, n, c, v = alu(ALU_ADD, self.regs[rs], sext6(imm) & 0xFF)
            self._wr(rd, res)
            self._flags(z, n, c, v)
        elif op == 0xF:                    # extended group
            if func == 0x0:
                pass                       # NOP
            elif func == 0x1:
                raise AssertionError("HALT must be handled by run()")
            elif func == 0x2:              # RET
                next_pc = self.regs[7]
            elif func == 0x3:              # CMP: SUB flags only
                _, z, n, c, v = alu(ALU_SUB, self.regs[rs], self.regs[rt])
                self._flags(z, n, c, v)
            # func 0x4..0x7 reserved -> NOP
        self.pc = next_pc
        self.cycles += 1

    def run(self):
        while not self.halted and self.cycles < self.max_cycles:
            if self._is_halt(self.rom[self.pc]):
                self.halted = True
                break
            self.step()
        if not self.halted and self.cycles >= self.max_cycles:
            self.timeout = True
        return self

    # -- observation -----------------------------------------------------
    def state(self):
        return {
            "pc": self.pc,
            "flags": {"z": self.z, "n": self.n, "c": self.c, "v": self.v},
            "regs": list(self.regs),
            "ram": list(self.ram),
            "cycles": self.cycles,
            "halted": self.halted,
            "timeout": self.timeout,
        }

    def compact(self):
        s = self.state()
        f = s["flags"]
        return (f"pc=0x{s['pc']:02X} flags=ZNCV={f['z']}{f['n']}{f['c']}{f['v']} "
                f"cycles={s['cycles']} halted={int(s['halted'])} "
                f"timeout={int(s['timeout'])} regs=" +
                " ".join(f"r{i}=0x{v:02X}" for i, v in enumerate(s["regs"])))


def run_source(text, max_cycles=100000):
    result = assembler.assemble_with_data(text)
    cpu = MiniCPU8(result.words, result.ram, max_cycles=max_cycles)
    return cpu.run(), result


def main():
    ap = argparse.ArgumentParser(description="MiniCPU-8 ISA v2 golden model")
    ap.add_argument("input", help=".asm source file")
    ap.add_argument("--json", action="store_true", help="print final state as JSON")
    ap.add_argument("--ram", action="store_true", help="print all 256 RAM bytes")
    ap.add_argument("--max-cycles", type=int, default=100000)
    args = ap.parse_args()

    try:
        with open(args.input) as f:
            cpu, _ = run_source(f.read(), args.max_cycles)
    except assembler.AsmError as e:
        sys.exit(str(e))
    except OSError as e:
        sys.exit(f"isa_sim: cannot read {args.input}: {e}")

    if args.json:
        print(json.dumps(cpu.state(), sort_keys=True))
        return
    print(cpu.compact())
    if args.ram:
        for base in range(0, 256, 16):
            chunk = " ".join(f"{b:02X}" for b in cpu.ram[base:base + 16])
            print(f"RAM {base:02X}: {chunk}")
    else:
        nz = [f"[{i:02X}]={b:02X}" for i, b in enumerate(cpu.ram) if b]
        print("RAM nonzero: " + (" ".join(nz) if nz else "(all zero)"))
    if cpu.timeout:
        sys.exit("isa_sim: program exceeded --max-cycles")
    if not cpu.halted:
        sys.exit("isa_sim: program did not halt")


if __name__ == "__main__":
    main()
