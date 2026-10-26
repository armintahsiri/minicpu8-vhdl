#!/usr/bin/env python3
"""Apply isolated one-line RTL mutations and check the repository suite.

Every case runs in its own temporary source copy; the working RTL is never
edited. Detection is classified by the first failing command/testbench in
`make test`. The JSON matrix is written under build/ for repeatable reporting.
"""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IGNORES = shutil.ignore_patterns(".git", "work", "build", "__pycache__", "*.pyc")

# id, description, file, exact old line/text, exact replacement
MUTATIONS = [
    (1, "ADD carry flag", "alu.vhd", "        cf  := sum(8);\n", "        cf  := '0';\n"),
    (2, "ADD overflow flag", "alu.vhd", "vf  := (a(7) xnor b(7)) and (a(7) xor res(7));", "vf  := (a(7) xor b(7)) and (a(7) xor res(7));"),
    (3, "SUB carry/no-borrow flag", "alu.vhd", "cf  := sum(8);                      -- 1 = no borrow (ARM convention)", "cf  := not sum(8);                   -- mutation"),
    (4, "logic operation C flag", "alu.vhd", "when ALU_AND    => res := ua and ub;   -- C and V cleared", "when ALU_AND    => res := ua and ub; cf := '1';"),
    (5, "SHL shifted-out carry", "alu.vhd", "cf  := ua(7);                       -- bit shifted out", "cf  := ua(0);                       -- mutated"),
    (6, "SHR shifted-out carry", "alu.vhd", "cf  := ua(0);                       -- bit shifted out", "cf  := ua(7);                       -- mutated"),
    (7, "LOADI sign extension", "cpu_top.vhd", "resize(signed(instr(5 downto 0)), 8)", "resize(unsigned(instr(5 downto 0)), 8)"),
    (8, "R0 write guard", "register_file.vhd", "if we = '1' and waddr /= \"000\" then", "if we = '1' then"),
    (9, "PC-relative branch base", "cpu_top.vhd", "unsigned(pc_plus1) + unsigned(imm_ext)", "unsigned(pc_q) + unsigned(imm_ext)"),
    (10, "MMIO lower-bound decode", "cpu_top.vhd", "unsigned(ram_addr) >= unsigned(IO_BASE)", "unsigned(ram_addr) > unsigned(IO_BASE)"),
    (11, "UART busy write policy", "mmio.vhd", "addr = IO_UART_TX and uart_busy = '0'", "addr = IO_UART_TX"),
    (12, "GPIO synchronizer stage", "gpio.vhd", "sync <= meta;", "sync <= pin_in;"),
    (13, "reset register-write gate", "cpu_top.vhd", "rf_we   <= reg_write and not rst and not load_stall_active;", "rf_we   <= reg_write;"),
    (14, "PC reset value", "pc.vhd", "cnt <= (others => '0');", "cnt <= cnt;"),
    (15, "SHL data result", "alu.vhd", "res := ua(6 downto 0) & '0';", "res := '0' & ua(7 downto 1);"),
    (16, "CMP flag write", "control_unit.vhd", "when FUNC_CMP  => flag_write <= '1'; alu_op <= ALU_SUB;", "when FUNC_CMP  => null;"),
    (17, "CALL link stores wrong value", "control_unit.vhd", "link <= '1'; reg_write <= '1'; wb_sel <= WB_PC1;", "link <= '1'; reg_write <= '1'; wb_sel <= WB_ALU;"),
    (18, "RET target source", "cpu_top.vhd", "                 rd1               when PC_R7,", "                 pc_plus1          when PC_R7,"),
    (19, "BCS/BCC branch decode", "branch_cond.vhd", "when COND_BCS => taken <= c;      -- unsigned >=", "when COND_BCS => taken <= not c;  -- mutated"),
    (20, "UART integer divisor", "uart_tx.vhd", "constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD;", "constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD - 1;"),
    (21, "RAM write enable", "data_ram.vhd", "if we = '1' then", "if we = '0' then"),
    (22, "UART busy status bit", "mmio.vhd", "rdata(0) <= uart_busy;", "rdata(0) <= not uart_busy;"),
    (23, "RAM effective address wrap", "cpu_top.vhd", "ram_addr <= alu_result when (mem_read = '1' or mem_write = '1')", "ram_addr <= std_logic_vector(unsigned(alu_result) + 1) when (mem_read = '1' or mem_write = '1')"),
    (24, "LOAD incorrectly writes flags", "control_unit.vhd", "reg_write <= '1'; mem_read <= '1'; alu_src_imm <= '1';", "reg_write <= '1'; mem_read <= '1'; flag_write <= '1'; alu_src_imm <= '1';"),
    (25, "STORE incorrectly writes flags", "control_unit.vhd", "mem_write <= '1'; alu_src_imm <= '1'; rd2_from_rd <= '1';", "mem_write <= '1'; flag_write <= '1'; alu_src_imm <= '1'; rd2_from_rd <= '1';"),
    (26, "JMP incorrectly writes flags", "control_unit.vhd", "when COND_JMP => pc_sel <= PC_ABS; cond_out <= COND_JMP;", "when COND_JMP => pc_sel <= PC_ABS; flag_write <= '1'; cond_out <= COND_JMP;"),
    (27, "BEQ selects rt from wrong field", "control_unit.vhd", "pc_sel <= PC_REL_EQ; rd2_from_rd <= '1';", "pc_sel <= PC_REL_EQ; rd2_from_rd <= '0';"),
    (28, "CMP writes rd register", "control_unit.vhd", "when FUNC_CMP  => flag_write <= '1'; alu_op <= ALU_SUB;", "when FUNC_CMP  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SUB;"),
    (29, "STORE selects data from wrong field", "control_unit.vhd", "mem_write <= '1'; alu_src_imm <= '1'; rd2_from_rd <= '1';", "mem_write <= '1'; alu_src_imm <= '1'; rd2_from_rd <= '0';"),
    (30, "BHS/BLO shared condition truth", "branch_cond.vhd", "when COND_BCS => taken <= c;      -- unsigned >=", "when COND_BCS => taken <= not c;  -- mutated shared alias"),
    (31, "reserved MMIO read value", "mmio.vhd", "rdata <= x\"00\";                       -- write-only / reserved reads", "rdata <= x\"FF\";                       -- mutated reserved value"),
    (32, "GPIO_OUT readback", "gpio.vhd", "rd_out  <= out_reg;", "rd_out  <= (others => '0');"),
    (33, "cycle-counter reset", "cycle_counter.vhd", "cnt <= (others => '0');", "cnt <= cnt;"),
    (34, "UART data order is MSB-first", "uart_tx.vhd", "tx_r    <= shift(0);         -- first data bit", "tx_r    <= shift(7);         -- mutated order"),
    (35, "SHL one-bit edge behavior", "alu.vhd", "res := ua(6 downto 0) & '0';        -- B ignored; 1-bit logical left", "res := '0' & ua(7 downto 1);        -- mutated shift"),
    (36, "HALT does not freeze PC", "cpu_top.vhd", "pc_en <= (not halt_int) and (not load_stall_active);", "pc_en <= not load_stall_active;"),
]


def classify(output, returncode):
    if "=== START " in output:
        for line in output.splitlines():
            if line.startswith("=== START "):
                parts = line.split()
                tb = parts[2] if len(parts) > 2 else "unknown"
                if f"=== PASS {tb} ===" not in output:
                    return "directed", tb
    if returncode != 0 and ("MISMATCHED" in output or "mismatch" in output.lower()):
        return "fuzz-only", "differential fuzz"
    if "FUZZ DIVERSITY" in output or "consistency check" in output:
        return "precheck", "consistency/diversity"
    if returncode == 0:
        return "undetected", ""
    return "build-or-precheck", "make test"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", type=int, nargs="*", help="run only these mutation ids")
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--simulation-only", action="store_true",
                        help="exclude consistency, diversity, assembler and model checks")
    args = parser.parse_args()
    selected = [m for m in MUTATIONS if args.only is None or m[0] in args.only]
    rows = []

    with tempfile.TemporaryDirectory(prefix="minicpu8-mutation-") as temp:
        base = Path(temp) / "base"
        shutil.copytree(ROOT, base, ignore=IGNORES)
        for mid, name, rel, old, new in selected:
            case = Path(temp) / f"case-{mid:02d}"
            shutil.copytree(base, case, ignore=IGNORES)
            src = case / rel
            text = src.read_text(encoding="utf-8")
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"mutation {mid}: expected one source match, found {count}: {old!r}")
            src.write_text(text.replace(old, new, 1), encoding="utf-8")
            try:
                target = "simulation-only" if args.simulation_only else "test"
                proc = subprocess.run(["make", target], cwd=case, text=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      timeout=args.timeout)
                output = proc.stdout
                rc = proc.returncode
            except subprocess.TimeoutExpired as exc:
                output = (exc.stdout or "")
                if isinstance(output, bytes):
                    output = output.decode(errors="replace")
                rc = 124
            category, detected_by = classify(output, rc)
            row = {"id": mid, "mutation": name, "file": rel,
                   "result": category, "detected_by": detected_by,
                   "returncode": rc}
            rows.append(row)
            print(f"{mid:02d} {name}: {category}" +
                  (f" ({detected_by})" if detected_by else ""))

    report = ROOT / "build" / "mutation-report.json"
    report.parent.mkdir(exist_ok=True)
    report.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    survivors = [row for row in rows if row["result"] == "undetected"]
    print(f"MUTATIONS: {len(rows) - len(survivors)}/{len(rows)} detected; "
          f"matrix={report}")
    if survivors:
        print("UNDETECTED: " + ", ".join(str(row["id"]) for row in survivors))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
