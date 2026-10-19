#!/usr/bin/env python3
"""Generate random, valid, terminating MiniCPU-8 assembly programs.

Design of the generator:
  * The main body is straight-line code with only *forward* branches, so every
    path reaches HALT (there are no backward loops to get wrong).
  * Every program contains all ALU and immediate operations.
  * Jump-group condition codes are cycled deterministically, so a small run
    covers BZ/BNZ/BCS/BHS/BCC/BLO/BN/BLT/BGE and BEQ/BNE/JMP.
  * Every program starts with a CALL.  Both a leaf subroutine and a nested
    subroutine (which saves/restores R7 in RAM[250]) are emitted.
  * LOAD/STORE use a randomly initialized data RAM; addresses wrap naturally.
  * A fixed seed makes a run reproducible.

Usage:
  python3 tools/random_programs.py --count 5 --seed 1 --out build/asm
"""
import argparse
import os
import random
import sys
from dataclasses import dataclass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assembler  # noqa: E402

MANDATORY = ["add", "sub", "and", "or", "xor", "not", "shl", "shr",
             "mov", "addi", "subi", "loadi", "cmp", "load", "store", "nop"]

BRANCH_KINDS = ["bz", "bnz", "bhs", "blo", "bcs", "bcc", "bn", "bnn",
                "blt", "bge", "beq", "bne", "jmp"]


@dataclass
class GeneratedProgram:
    index: int
    name: str
    asm: str


def _reg(rng, allow_r0=True):
    return rng.randint(0, 7) if allow_r0 else rng.randint(1, 7)


def _dst(rng, safe=False):
    return rng.randint(1, 6) if safe else rng.randint(1, 7)


def _imm(rng, lo=-32, hi=31):
    return rng.randint(lo, hi)


def normal_instr(rng, safe=False):
    """A random instruction that is not a branch, call, HALT or RET."""
    kinds = ["add", "sub", "and", "or", "xor", "not", "shl", "shr",
             "mov", "addi", "subi", "loadi", "cmp", "load", "store", "nop"]
    k = rng.choice(kinds)
    if k == "nop":
        return "nop"
    d = _dst(rng, safe)
    s1 = _reg(rng)
    s2 = _reg(rng)
    if k in ("add", "sub", "and", "or", "xor"):
        return f"{k} r{d}, r{s1}, r{s2}"
    if k in ("not", "shl", "shr"):
        return f"{k} r{d}, r{s1}"
    if k == "mov":
        return f"mov r{d}, r{s1}"
    if k == "addi":
        return f"addi r{d}, r{s1}, {_imm(rng, -16, 31)}"
    if k == "subi":
        return f"subi r{d}, r{s1}, {_imm(rng, -16, 16)}"
    if k == "loadi":
        return f"loadi r{d}, {_imm(rng)}"
    if k == "cmp":
        return f"cmp r{s1}, r{s2}"
    if k == "load":
        return f"load r{d}, [r{s1}{_imm_text(rng)}]"
    if k == "store":
        return f"store r{s2}, [r{s1}{_imm_text(rng)}]"
    raise AssertionError(k)


def _imm_text(rng):
    v = rng.randint(-16, 16)
    return ("+" if v >= 0 else "-") + str(abs(v))


def mandatory_instr(rng, kind):
    if kind == "nop":
        return "nop"
    d = _dst(rng)
    s1 = _reg(rng)
    s2 = _reg(rng)
    if kind in ("add", "sub", "and", "or", "xor"):
        return f"{kind} r{d}, r{s1}, r{s2}"
    if kind in ("not", "shl", "shr"):
        return f"{kind} r{d}, r{s1}"
    if kind == "mov":
        return f"mov r{d}, r{s1}"
    if kind == "addi":
        return f"addi r{d}, r{s1}, {_imm(rng, -16, 31)}"
    if kind == "subi":
        return f"subi r{d}, r{s1}, {_imm(rng, -16, 16)}"
    if kind == "loadi":
        return f"loadi r{d}, {_imm(rng)}"
    if kind == "cmp":
        return f"cmp r{s1}, r{s2}"
    if kind == "load":
        return f"load r{d}, [r{s1}{_imm_text(rng)}]"
    if kind == "store":
        return f"store r{s2}, [r{s1}{_imm_text(rng)}]"
    raise AssertionError(kind)


def branch_instr(rng, i, length, labels_at, label_no, kind):
    """Forward branch: target is 1..4 slots ahead (or the HALT at length)."""
    if kind in ("beq", "bne"):
        s1 = _reg(rng)
        s2 = _reg(rng)
        d = rng.randint(1, 4)
        target = min(i + 1 + d, length)
        lbl = f"L{label_no}"
        labels_at.setdefault(target, []).append(lbl)
        return f"{kind} r{s1}, r{s2}, {lbl}"
    d = rng.randint(1, 4)
    target = min(i + 1 + d, length)
    lbl = f"L{label_no}"
    labels_at.setdefault(target, []).append(lbl)
    return f"{kind} {lbl}"


def leaf_instr(rng):
    # Never write R7 inside a subroutine: RET depends on the link.
    return normal_instr(rng, safe=True)


def safe_leaf_instr(rng):
    """ALU/immediate-only instruction: no RAM, so it cannot clobber the
    nested-call link saved at RAM[250]."""
    kinds = ["add", "sub", "and", "or", "xor", "not", "shl", "shr",
             "mov", "addi", "subi", "loadi", "cmp", "nop"]
    k = rng.choice(kinds)
    if k == "nop":
        return "nop"
    d = rng.randint(1, 6)          # never R7
    s1 = _reg(rng)
    s2 = _reg(rng)
    if k in ("add", "sub", "and", "or", "xor"):
        return f"{k} r{d}, r{s1}, r{s2}"
    if k in ("not", "shl", "shr"):
        return f"{k} r{d}, r{s1}"
    if k == "mov":
        return f"mov r{d}, r{s1}"
    if k == "addi":
        return f"addi r{d}, r{s1}, {_imm(rng, -16, 31)}"
    if k == "subi":
        return f"subi r{d}, r{s1}, {_imm(rng, -16, 16)}"
    if k == "loadi":
        return f"loadi r{d}, {_imm(rng)}"
    if k == "cmp":
        return f"cmp r{s1}, r{s2}"
    raise AssertionError(k)


def generate_one(index, seed):
    rng = random.Random((seed * 1000003) ^ (index * 9176 + 17))
    length = rng.randint(24, 32)
    slots = [None] * length
    labels_at = {}
    label_no = 0

    # Data RAM: a small random array at a low-ish address.
    data_base = rng.randint(16, 40)
    data_len = rng.randint(8, 20)
    data_vals = [rng.randint(-128, 255) for _ in range(data_len)]

    # Slot 0 is always a CALL so every program exercises CALL/RET.
    slots[0] = "call " + ("nested" if index % 2 == 0 else "leaf0")

    # Mandatory instruction coverage.
    mandatory_slots = rng.sample(range(1, length), len(MANDATORY))
    for idx, kind in zip(mandatory_slots, MANDATORY):
        slots[idx] = mandatory_instr(rng, kind)

    free = [i for i in range(1, length) if slots[i] is None]
    rng.shuffle(free)

    # One extra call in half the programs.
    if free and index % 3 == 0:
        slots[free.pop()] = "call " + ("leaf0" if index % 2 else "nested")

    # Four deterministic-kind forward branches.
    for b in range(4):
        if not free:
            break
        i = free.pop()
        kind = BRANCH_KINDS[(index * 4 + b) % len(BRANCH_KINDS)]
        slots[i] = branch_instr(rng, i, length, labels_at, label_no, kind)
        label_no += 1

    # Fill everything else with random normal instructions.
    for i in free:
        slots[i] = normal_instr(rng)

    lines = []
    lines.append(f"; fuzz program {index} (seed {seed})")
    lines.append(".data " + ", ".join([str(data_base)] + [str(v) for v in data_vals]))
    lines.append("main:")
    for i in range(length):
        for lbl in labels_at.get(i, []):
            lines.append(f"{lbl}:")
        lines.append("        " + slots[i])
    for lbl in labels_at.get(length, []):
        lines.append(f"{lbl}:")
    lines.append("        halt")

    lines.append("leaf0:")
    for _ in range(rng.randint(5, 8)):
        lines.append("        " + leaf_instr(rng))
    lines.append("        ret")

    lines.append("leaf_safe:")
    for _ in range(rng.randint(3, 6)):
        lines.append("        " + safe_leaf_instr(rng))
    lines.append("        ret")

    lines.append("nested:")
    lines.append("        store r7, [r0-6]")   # RAM[250], clear of the data array
    lines.append("        call leaf_safe")     # memory-free: cannot clobber RAM[250]
    lines.append("        load r7, [r0-6]")
    lines.append("        ret")

    asm = "\n".join(lines) + "\n"
    return GeneratedProgram(index=index, name=f"fuzz_{index:03d}", asm=asm)


def generate_programs(count, seed=20251019):
    programs = [generate_one(i, seed) for i in range(count)]
    # Validate every program with the real assembler before handing it on.
    for p in programs:
        try:
            assembler.assemble_with_data(p.asm)
        except assembler.AsmError as e:
            raise RuntimeError(f"generated program {p.name} does not assemble: {e}\n{p.asm}")

    # Static coverage: every required mnemonic must appear somewhere.
    import re
    seen = set()
    for p in programs:
        for raw in p.asm.splitlines():
            code = re.sub(r"\s+", " ", raw.split(";")[0]).strip()
            if not code or code.startswith("."):
                continue
            while True:
                m = re.match(r"^[A-Za-z_][A-Za-z0-9_]*:\s*", code)
                if not m:
                    break
                code = code[m.end():]
            if code:
                seen.add(code.split()[0].lower())
    required = set(MANDATORY) | {"call", "ret", "halt"}
    # Four branch slots per program cover all 13 kinds by about program 4.
    if count >= 4:
        required |= set(BRANCH_KINDS)
    missing = required - seen
    if missing:
        raise RuntimeError("random generator coverage missing: " +
                           ", ".join(sorted(missing)))
    return programs


def main():
    ap = argparse.ArgumentParser(description="MiniCPU-8 random program generator")
    ap.add_argument("--count", type=int, default=20)
    ap.add_argument("--seed", type=int, default=20251019)
    ap.add_argument("--out", help="write .asm files to this directory")
    args = ap.parse_args()
    programs = generate_programs(args.count, args.seed)
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for p in programs:
            path = os.path.join(args.out, p.name + ".asm")
            with open(path, "w") as f:
                f.write(p.asm)
            print(path)
    else:
        for p in programs:
            print(f"; ==== {p.name} ====")
            print(p.asm)


if __name__ == "__main__":
    main()
