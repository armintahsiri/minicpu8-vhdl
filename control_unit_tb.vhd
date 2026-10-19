-- control_unit_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Exhaustive decode assertion: every opcode (0..15) x every extended
-- function (0..7) x every jump-group condition (0..15), checking ALL control
-- outputs.  Reserved function/condition codes must decode as a complete NOP.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity control_unit_tb is
end entity control_unit_tb;

architecture sim of control_unit_tb is
  type alu_array_t is array (0 to 7) of alu_op_t;
  constant ALU_BY_OP : alu_array_t :=
    (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_NOT, ALU_XOR, ALU_SHL, ALU_SHR);

  type cond_array_t is array (0 to 15) of cond_code_t;
  constant COND_BY_CODE : cond_array_t :=
    (COND_JMP, COND_BZ, COND_BNZ, COND_BCS, COND_BCC, COND_BN, COND_BNN,
     COND_BLT, COND_BGE, "1001", "1010", "1011", "1100", "1101", "1110",
     COND_CALL);

  signal opcode    : opcode_t := (others => '0');
  signal func      : func_t := (others => '0');
  signal cond_code : cond_code_t := (others => '0');

  signal reg_write, mem_read, mem_write, flag_write : std_logic;
  signal alu_src_imm, rd2_from_rd, link, halt : std_logic;
  signal alu_op    : alu_op_t;
  signal wb_sel    : wb_sel_t;
  signal pc_sel    : pc_sel_t;
  signal cond_out  : cond_code_t;
begin

  dut : entity work.control_unit
    port map (opcode => opcode, func => func, cond_code => cond_code,
              reg_write => reg_write, mem_read => mem_read,
              mem_write => mem_write, flag_write => flag_write,
              alu_src_imm => alu_src_imm, rd2_from_rd => rd2_from_rd,
              alu_op => alu_op, wb_sel => wb_sel, pc_sel => pc_sel,
              cond_out => cond_out, link => link, halt => halt);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure run_case (opi, fi, ci : integer) is
      variable e_rw, e_mr, e_mw, e_fw : std_logic := '0';
      variable e_imm, e_rd2, e_link, e_halt : std_logic := '0';
      variable e_alu  : alu_op_t := ALU_ADD;
      variable e_wb   : wb_sel_t := WB_ALU;
      variable e_pc   : pc_sel_t := PC_NEXT;
      variable e_cond : cond_code_t := COND_JMP;
      variable bad : boolean := false;
    begin
      -- Independent reference decode (docs/ISA.md).
      case opi is
        when 0 to 7 =>
          e_rw := '1'; e_fw := '1'; e_alu := ALU_BY_OP(opi);
        when 8 =>                          -- LOAD
          e_rw := '1'; e_mr := '1'; e_imm := '1';
          e_alu := ALU_ADD; e_wb := WB_MEM;
        when 9 =>                          -- LOADI
          e_rw := '1'; e_imm := '1'; e_alu := ALU_PASS_B;
        when 10 =>                         -- BEQ
          e_pc := PC_REL_EQ; e_rd2 := '1';
        when 11 =>                         -- BNE
          e_pc := PC_REL_NE; e_rd2 := '1';
        when 12 =>                         -- jump group
          case ci is
            when 0 => e_pc := PC_ABS; e_cond := COND_JMP;
            when 1 => e_pc := PC_ABS; e_cond := COND_BZ;
            when 2 => e_pc := PC_ABS; e_cond := COND_BNZ;
            when 3 => e_pc := PC_ABS; e_cond := COND_BCS;
            when 4 => e_pc := PC_ABS; e_cond := COND_BCC;
            when 5 => e_pc := PC_ABS; e_cond := COND_BN;
            when 6 => e_pc := PC_ABS; e_cond := COND_BNN;
            when 7 => e_pc := PC_ABS; e_cond := COND_BLT;
            when 8 => e_pc := PC_ABS; e_cond := COND_BGE;
            when 15 =>
              e_pc := PC_ABS; e_cond := COND_JMP;
              e_link := '1'; e_rw := '1'; e_wb := WB_PC1;
            when others => null;         -- 9..14 reserved: NOP
          end case;
        when 13 =>                         -- STORE
          e_mw := '1'; e_imm := '1'; e_rd2 := '1'; e_alu := ALU_ADD;
        when 14 =>                         -- ADDI
          e_rw := '1'; e_fw := '1'; e_imm := '1'; e_alu := ALU_ADD;
        when 15 =>                         -- extended group
          case fi is
            when 0 => null;              -- NOP
            when 1 => e_halt := '1'; e_pc := PC_HOLD;
            when 2 => e_pc := PC_R7;
            when 3 => e_fw := '1'; e_alu := ALU_SUB;
            when others => null;         -- 4..7 reserved: NOP
          end case;
        when others => null;
      end case;

      opcode    <= std_logic_vector(to_unsigned(opi, 4));
      func      <= std_logic_vector(to_unsigned(fi, 3));
      cond_code <= std_logic_vector(to_unsigned(ci, 4));
      wait for 1 ns;
      checks := checks + 1;

      if reg_write /= e_rw or mem_read /= e_mr or mem_write /= e_mw or
         flag_write /= e_fw or alu_src_imm /= e_imm or rd2_from_rd /= e_rd2 or
         alu_op /= e_alu or wb_sel /= e_wb or pc_sel /= e_pc or
         cond_out /= e_cond or link /= e_link or halt /= e_halt then
        bad := true;
      end if;

      if bad then
        errors := errors + 1;
        report "FAIL op=" & integer'image(opi) & " func=" & integer'image(fi) &
               " cond=" & integer'image(ci) &
               " got rw/mr/mw/fw/imm/rd2=" & to_string(reg_write) &
               to_string(mem_read) & to_string(mem_write) & to_string(flag_write) &
               to_string(alu_src_imm) & to_string(rd2_from_rd) &
               " alu=" & alu_op_t'image(alu_op) &
               " wb=" & wb_sel_t'image(wb_sel) &
               " pc=" & pc_sel_t'image(pc_sel) &
               " cond=" & to_string(cond_out) &
               " link=" & to_string(link) & " halt=" & to_string(halt) &
               " expected rw/mr/mw/fw/imm/rd2=" & to_string(e_rw) &
               to_string(e_mr) & to_string(e_mw) & to_string(e_fw) &
               to_string(e_imm) & to_string(e_rd2) &
               " alu=" & alu_op_t'image(e_alu) &
               " wb=" & wb_sel_t'image(e_wb) &
               " pc=" & pc_sel_t'image(e_pc) &
               " cond=" & to_string(e_cond) &
               " link=" & to_string(e_link) & " halt=" & to_string(e_halt)
          severity error;
      end if;
    end procedure;
  begin
    for opi in 0 to 15 loop
      for fi in 0 to 7 loop
        for ci in 0 to 15 loop
          run_case(opi, fi, ci);
        end loop;
      end loop;
    end loop;

    report "control_unit_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "CONTROL UNIT TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "CONTROL UNIT TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
