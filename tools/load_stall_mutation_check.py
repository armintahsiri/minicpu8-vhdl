#!/usr/bin/env python3
"""Spot-check the EXPERIMENTAL LOAD_STALL control with five RTL mutations."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NVC = shutil.which("nvc")
if not NVC:
    raise SystemExit("load_stall_mutation_check: nvc is required")

MUTATIONS = {
    "PC advances during wait": (
        "pc_en <= (not halt_int) and (not load_stall_active);",
        "pc_en <= not halt_int;"),
    "register write is not suppressed": (
        "rf_we   <= reg_write and not rst and not load_stall_active;",
        "rf_we   <= reg_write and not rst;"),
    "wait state never arms": (
        "load_wait_q <= load_stall_active;",
        "load_wait_q <= '0';"),
    "MMIO LOAD skips wait": (
        "load_stall_active <= mem_read and not load_wait_q when LOAD_STALL else '0';",
        "load_stall_active <= mem_read and not io_sel and not load_wait_q when LOAD_STALL else '0';"),
    "synchronous RAM read is stuck at zero": (
        "rdata <= mem(to_integer(unsigned(addr)));",
        "rdata <= (others => '0');"),
}

CORE = ["minicpu_pkg.vhd", "alu.vhd", "register_file.vhd", "flag_reg.vhd",
        "pc.vhd", "instr_rom.vhd", "data_ram.vhd", "branch_cond.vhd",
        "control_unit.vhd", "uart_tx.vhd", "gpio.vhd", "cycle_counter.vhd",
        "mmio.vhd", "cpu_top.vhd"]

with tempfile.TemporaryDirectory(prefix="minicpu8-loadstall-mut-") as tmp:
    base = Path(tmp)
    passed = 0
    for index, (name, (old, new)) in enumerate(MUTATIONS.items(), 1):
        case = base / str(index)
        case.mkdir()
        for filename in CORE + ["uart_rx_model.vhd", "load_stall_tb.vhd",
                                "load_stall_demo_rom.vhd"]:
            shutil.copy2(ROOT / filename, case / filename)
        target_name = "data_ram.vhd" if "RAM read" in name else "cpu_top.vhd"
        target = case / target_name
        source = target.read_text()
        if "RAM read" in name:
            start = source.index("\n  sync_read_gen")
            prefix, body = source[:start], source[start:]
            if old not in body:
                raise SystemExit(f"mutation anchor missing: {name}")
            source = prefix + body.replace(old, new, 1)
            target.write_text(source)
            old = None
        if old is not None and old not in source:
            raise SystemExit(f"mutation anchor missing: {name}")
        if old is not None:
            target.write_text(source.replace(old, new, 1))
        subprocess.run([NVC, "--std=08", "--work=work", "--init"], cwd=case,
                       check=True, stdout=subprocess.DEVNULL)
        units = CORE + ["uart_rx_model.vhd", "load_stall_demo_rom.vhd",
                        "load_stall_tb.vhd"]
        compile_result = subprocess.run(
            [NVC, "--std=08", "--work=work", "-a"] + units, cwd=case,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if compile_result.returncode:
            raise SystemExit(f"mutation compile failed ({name}):\n{compile_result.stdout}")
        run = subprocess.run([NVC, "--std=08", "--work=work", "-e",
                              "load_stall_tb", "-r"], cwd=case,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True)
        if run.returncode == 0:
            raise SystemExit(f"SURVIVED: {name}\n{run.stdout[-2000:]}")
        passed += 1
        print(f"  caught {index}/5: {name}")

print(f"LOAD_STALL MUTATIONS: {passed}/5 caught")
