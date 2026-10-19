#!/usr/bin/env python3
"""Cross-check the MiniCPU-8 ISA specification.

The single sources of truth are:
  * docs/ISA.md          -- the human-readable specification
  * tools/assembler.py   -- the encoder
  * minicpu_pkg.vhd      -- the hardware opcode/function/condition constants
  * cpu_top.vhd          -- the datapath field wiring

This script parses the tables and fails (exit 1) on any mismatch.  It is run
by `make test`, so the copies can never drift silently.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
sys.path.insert(0, TOOLS)
import assembler  # noqa: E402
import isa_sim    # noqa: E402

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


def normalize(s):
    return re.sub(r"\s+", "", s).lower()


def section(text, start, end):
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]


def parse_constants(text):
    """Return {name: (type, int_value)} for OPC_/FUNC_/COND_ constants."""
    out = {}
    pat = (r'constant\s+((?:OPC|FUNC|COND)_[A-Z0-9_]+)\s*:\s*'
           r'(opcode_t|func_t|cond_code_t)\s*:=\s*"([01]+)"')
    for name, typ, bits in re.findall(pat, text):
        out[name] = (typ, int(bits, 2), len(bits))
    return out


def parse_io_constants(text):
    """Return {name: int} for RAM_LAST / IO_* byte constants in the package."""
    pat = (r'constant\s+(RAM_LAST|IO_[A-Z0-9_]+)\s*:\s*byte_t\s*:=\s*'
           r'x"([0-9A-Fa-f]{2})"')
    return {name: int(value, 16) for name, value in re.findall(pat, text)}


def parse_io_doc_table(sec):
    """Parse '| `0xNN` | `NAME` | ...' rows from the I/O map table."""
    rows = {}
    for line in sec.splitlines():
        m = re.match(r'^\|\s*`0x([0-9A-Fa-f]{2})`\s*\|\s*`([A-Z0-9_]+)`\s*\|', line)
        if m:
            rows[int(m.group(1), 16)] = m.group(2)
    return rows


def parse_doc_table(sec):
    """Parse markdown rows '| `0xN` | MNEMONIC ...' -> {opcode: mnemonic}."""
    rows = {}
    for line in sec.splitlines():
        m = re.match(r'^\|\s*`0x([0-9A-Fa-f])`\s*\|\s*([^|]+?)\s*\|', line)
        if not m:
            continue
        value = int(m.group(1), 16)
        label = m.group(2).strip().replace("`", "").replace("*", "").strip()
        first = label.split()[0] if label.split() else ""
        if not first or first.lower().startswith("reserved"):
            continue
        rows[value] = first
    return rows


print("ISA consistency check:")

pkg_text = read("minicpu_pkg.vhd")
doc_text = read("docs/ISA.md")
cpu_text = read("cpu_top.vhd")
asm_text = read("tools/assembler.py")

consts = parse_constants(pkg_text)
doc_opcode_sec = section(doc_text, "## 2. Opcode map", "Pseudo-instructions")
doc_cond_sec = section(doc_text, "## 3. Jump group", "### Jump-group bit layout")
doc_func_sec = section(doc_text, "## 4. Extended group", "## 5. Flags")
doc_ops = parse_doc_table(doc_opcode_sec)       # opcode -> MNEMONIC
doc_conds = parse_doc_table(doc_cond_sec)       # cond   -> MNEMONIC
doc_funcs = parse_doc_table(doc_func_sec)       # func   -> MNEMONIC

ok("package defines 16 opcode constants",
   len([n for n in consts if n.startswith("OPC_")]) == 16,
   f"found {len([n for n in consts if n.startswith('OPC_')])}")
ok("package defines 4 extended functions",
   len([n for n in consts if n.startswith("FUNC_")]) == 4)
ok("package defines 10 jump-group conditions",
   len([n for n in consts if n.startswith("COND_")]) == 10)

# ---- opcode constants vs assembler and docs ------------------------------
for name, (typ, value, width) in sorted(consts.items()):
    if not name.startswith("OPC_"):
        continue
    mnem = name[len("OPC_"):].upper()
    ok(f"pkg {name}=0x{value:X} is a 4-bit opcode_t", typ == "opcode_t" and width == 4)
    ok(f"assembler has {mnem}=0x{value:X}",
       assembler.OPCODES.get(mnem) == value,
       f"assembler has {assembler.OPCODES.get(mnem)}")
    ok(f"docs opcode table has {mnem} at 0x{value:X}",
       doc_ops.get(value) == mnem, f"docs has {doc_ops.get(value)}")

ok("docs opcode table covers all 16 opcodes",
   set(doc_ops) == set(range(16)), f"docs covers {sorted(doc_ops)}")

# ---- extended function constants vs assembler and docs -------------------
for name, (typ, value, width) in sorted(consts.items()):
    if not name.startswith("FUNC_"):
        continue
    mnem = name[len("FUNC_"):].lower()
    ok(f"pkg {name}={value} is a 3-bit func_t", typ == "func_t" and width == 3)
    ok(f"assembler has function {mnem}={value}",
       assembler.FUNC.get(mnem) == value,
       f"assembler has {assembler.FUNC.get(mnem)}")
    ok(f"docs function table has {mnem.upper()} at {value}",
       doc_funcs.get(value) == mnem.upper(), f"docs has {doc_funcs.get(value)}")

# ---- jump-group condition constants vs assembler and docs ----------------
for name, (typ, value, width) in sorted(consts.items()):
    if not name.startswith("COND_"):
        continue
    mnem = name[len("COND_"):].lower()
    ok(f"pkg {name}=0x{value:X} is a 4-bit cond_code_t",
       typ == "cond_code_t" and width == 4)
    ok(f"assembler has condition {mnem}=0x{value:X}",
       assembler.COND.get(mnem) == value,
       f"assembler has {assembler.COND.get(mnem)}")
    ok(f"docs condition table has {mnem.upper()} at 0x{value:X}",
       doc_conds.get(value) == mnem.upper(), f"docs has {doc_conds.get(value)}")

ok("BCS/BHS are aliases", assembler.COND.get("bcs") == assembler.COND.get("bhs"))
ok("BCC/BLO are aliases", assembler.COND.get("bcc") == assembler.COND.get("blo"))
ok("docs shows BCS before its BHS alias", doc_conds.get(3) == "BCS")
ok("docs shows BCC before its BLO alias", doc_conds.get(4) == "BCC")

# ---- special words --------------------------------------------------------
ok("NOP_WORD is 0xF000", 'constant NOP_WORD  : word_t := x"F000"' in pkg_text)
ok("HALT_WORD is 0xF001", 'constant HALT_WORD : word_t := x"F001"' in pkg_text)
ok("assembler NOP_WORD matches package", assembler.NOP_WORD == 0xF000)
ok("assembler HALT_WORD matches package", assembler.HALT_WORD == 0xF001)

# ---- BEQ/BNE operand layout: rt lives in the rd field --------------------
# The assembler must encode beq r5,r5,+1 as 0xAB41: op=A, "rd"=5 (rt),
# rs=5, imm=1.  ISA.md documents the same example and the normative marker.
beq_word = assembler.assemble("beq r5, r5, 1")[0]
ok("assembler puts BEQ rt in the rd field (0xAB41)", beq_word == 0xAB41,
   f"got 0x{beq_word:04X}")
ok("ISA.md documents the 0xAB41 layout example", "0xAB41" in doc_text)
ok("ISA.md contains the normative BEQ/BNE layout marker",
   normalize(assembler.BEQ_BNE_LAYOUT) in normalize(doc_text))
ok("assembler source documents the rd-field trick",
   "rt" in asm_text and "rd field" in asm_text.lower())

# cpu_top reads rs on port 1 and selects the rd field for the second
# BEQ/BNE comparand.
cpu_norm = normalize(cpu_text)
ok("cpu_top reads rs field [8:6] on register port 1",
   "raddr1=>addr1" in cpu_norm and "elseinstr(8downto6)" in cpu_norm)
ok("cpu_top uses control's rd2_from_rd to select bits [11:9]",
   "addr2<=instr(11downto9)whenrd2_from_rd='1'elseinstr(5downto3)" in cpu_norm)

# ---- STORE / LOAD layouts ------------------------------------------------
store_word = assembler.assemble("store r7, [r1-32]")[0]
ok("assembler puts STORE data register in the rd field (0xDE60)",
   store_word == 0xDE60, f"got 0x{store_word:04X}")
ok("ISA.md contains the normative STORE layout marker",
   normalize(assembler.STORE_LAYOUT) in normalize(doc_text))
load_word = assembler.assemble("load r3, [r4+7]")[0]
ok("assembler LOAD layout example (0x8707)", load_word == 0x8707,
   f"got 0x{load_word:04X}")
ok("ISA.md contains the normative LOAD layout marker",
   normalize(assembler.LOAD_LAYOUT) in normalize(doc_text))

# ---- data RAM / CALL-RET conventions in spec and package -----------------
ok("package defines a 256-byte ram_t",
   "typeram_tisarray(0to255)ofbyte_t" in normalize(pkg_text))
ok("ISA.md documents 256 x 8 data RAM", "256 bytes" in doc_text and "8-bit address" in doc_text)
ok("ISA.md documents address wrap", "(rs + sext(imm6)) mod 256" in doc_text)
ok("ISA.md documents the R7 link convention", "R7 <- (PC+1) mod 256" in doc_text)
ok("ISA.md documents no hardware stack", "no hardware stack" in doc_text.lower())

# ---- Phase 3 I/O map: package vs docs vs assembler vs golden model -------
io_consts = parse_io_constants(pkg_text)
doc_io_sec = section(doc_text, "## 8. I/O map (MMIO)",
                     "### UART transmitter")
doc_io = parse_io_doc_table(doc_io_sec)
asm_io = {name.upper(): addr for name, addr in assembler.IO_SYMBOLS.items()}

ok("package defines IO_BASE=0xF0", io_consts.get("IO_BASE") == 0xF0,
   f"found {io_consts.get('IO_BASE')}")
ok("package defines RAM_LAST=0xEF", io_consts.get("RAM_LAST") == 0xEF,
   f"found {io_consts.get('RAM_LAST')}")
ok("assembler RAM_LAST matches package",
   assembler.RAM_LAST == io_consts.get("RAM_LAST"))
ok("assembler IO_BASE matches package",
   assembler.IO_BASE == io_consts.get("IO_BASE"))
ok("documents 240-byte RAM window", "0x00..0xEF" in doc_text and
   "240" in doc_io_sec)
ok("docs show the I/O region", "0xF0..0xFF" in doc_io_sec)
ok("docs state busy writes are ignored", "ignored" in doc_io_sec.lower())
ok("docs state .data reaching I/O is rejected",
   ".data" in doc_text and "rejected" in doc_text.lower())

io_pkg_names = {
    "IO_UART_TX": "UART_TX",
    "IO_UART_STATUS": "UART_STATUS",
    "IO_GPIO_OUT": "GPIO_OUT",
    "IO_GPIO_IN": "GPIO_IN",
    "IO_CYCLE_LO": "CYCLE_COUNT_LO",
}
for pkg_name, sym in io_pkg_names.items():
    addr = io_consts.get(pkg_name)
    ok(f"package defines {pkg_name}=0x{addr:02X}" if addr is not None
       else f"package defines {pkg_name}", addr is not None)
    ok(f"assembler symbol {sym} matches {pkg_name}",
       asm_io.get(sym) == addr, f"assembler has {asm_io.get(sym)}")
    ok(f"docs I/O table has {sym} at 0x{addr:02X}" if addr is not None
       else f"docs I/O table has {sym}", doc_io.get(addr) == sym,
       f"docs has {doc_io.get(addr)}")
    sim_name = {
        "IO_UART_TX": "IO_UART_TX", "IO_UART_STATUS": "IO_UART_STATUS",
        "IO_GPIO_OUT": "IO_GPIO_OUT", "IO_GPIO_IN": "IO_GPIO_IN",
        "IO_CYCLE_LO": "IO_CYCLE_LO",
    }[pkg_name]
    ok(f"golden model {sim_name} matches package",
       getattr(isa_sim, sim_name) == addr,
       f"isa_sim has {getattr(isa_sim, sim_name)}")

ok("package defines reserved I/O range F5..FF",
   io_consts.get("IO_RESERVED_LO") == 0xF5 and
   io_consts.get("IO_RESERVED_HI") == 0xFF)
ok("assembler rejects .data into I/O",
   assembler.RAM_LAST == 0xEF)
try:
    assembler.assemble_with_data(".data 0xEF, 1, 2\nmain: nop")
    data_io_rejected = False
except assembler.AsmError:
    data_io_rejected = True
ok("assembler raises on .data across 0xEF/0xF0", data_io_rejected)

cpu_io_norm = normalize(cpu_text)
ok("cpu_top compares ram_addr numerically against IO_BASE",
   "unsigned(ram_addr)>=unsigned(io_base)" in cpu_io_norm)
ok("cpu_top gates data RAM writes with not io_sel",
   "ram_we_eff<=ram_weandnotio_sel" in cpu_io_norm)
ok("cpu_top instantiates mmio", "mmio_i:entitywork.mmio" in cpu_io_norm)
ok("cpu_top exposes uart_tx/gpio ports",
   "uart_tx:outstd_logic" in cpu_io_norm and
   "gpio_out:outbyte_t" in cpu_io_norm and
   "gpio_in:inbyte_t" in cpu_io_norm)

print()
if failures:
    print(f"ISA CONSISTENCY: FAILED ({len(failures)} of {checks} checks)")
    sys.exit(1)
print(f"ISA CONSISTENCY: ALL {checks} CHECKS PASSED")
