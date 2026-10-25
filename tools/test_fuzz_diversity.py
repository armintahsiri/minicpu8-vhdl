#!/usr/bin/env python3
"""Enforce structural diversity in the deterministic fuzz generators."""
import hashlib
import re
import sys

sys.path.insert(0, "tools")
import random_programs


def structure(asm):
    """Keep opcodes/registers/flow shape, erase comments, labels and literals."""
    result = []
    for raw in asm.splitlines():
        code = raw.split(";", 1)[0].strip().lower()
        if not code or code.startswith("."):
            continue
        code = re.sub(r"^[a-z_][a-z0-9_]*:\s*", "", code)
        if not code:
            continue
        code = re.sub(r"\b(?:0x[0-9a-f]+|[+-]?\d+)\b", "#", code)
        result.append(" ".join(code.split()))
    return "\n".join(result)


def check(name, programs):
    hashes = [hashlib.sha256(structure(p.asm).encode()).hexdigest()
              for p in programs]
    unique = len(set(hashes))
    ratio = unique / len(programs)
    print(f"{name}: {unique}/{len(programs)} structural fingerprints "
          f"({ratio:.1%})")
    if ratio < 0.90:
        raise SystemExit(f"{name} diversity below 90%")
    return unique, len(programs)


def main():
    n = 40
    normal = check("normal ALU/RAM", random_programs.generate_programs(
        n, 20251019))
    io = check("I/O", random_programs.generate_io_programs(n, 20251019))
    total_unique = normal[0] + io[0]
    total = normal[1] + io[1]
    ratio = total_unique / total
    print(f"overall: {total_unique}/{total} structural fingerprints "
          f"({ratio:.1%})")
    if ratio < 0.98:
        raise SystemExit("overall diversity below 98%")
    print("FUZZ DIVERSITY: ALL ASSERTIONS PASSED")


if __name__ == "__main__":
    main()
