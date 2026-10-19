-- control_unit_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Checks the decode outputs for every opcode (including reserved = NOP).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity control_unit_tb is
end entity control_unit_tb;

architecture sim of control_unit_tb is
  signal opcode      : opcode_t := (others => '0');
  signal reg_write   : std_logic;
  signal flag_write  : std_logic;
  signal alu_src_imm : std_logic;
  signal alu_op      : alu_op_t;
  signal branch      : branch_t;
  signal halt        : std_logic;
begin

  dut : entity work.control_unit
    port map (opcode => opcode, reg_write => reg_write,
              flag_write => flag_write, alu_src_imm => alu_src_imm,
              alu_op => alu_op, branch => branch, halt => halt);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure check (name : string; op : opcode_t;
                     e_rw, e_fw, e_imm : std_logic;
                     e_alu : alu_op_t; e_br : branch_t; e_halt : std_logic) is
    begin
      opcode <= op;
      wait for 1 ns;
      checks := checks + 1;
      if reg_write /= e_rw or flag_write /= e_fw or alu_src_imm /= e_imm or
         alu_op /= e_alu or branch /= e_br or halt /= e_halt then
        errors := errors + 1;
        report "FAIL " & name &
               " got rw/fw/imm=" & to_string(reg_write) & to_string(flag_write) &
               to_string(alu_src_imm) &
               " alu=" & alu_op_t'image(alu_op) &
               " br=" & branch_t'image(branch) &
               " halt=" & to_string(halt) &
               " expected rw/fw/imm=" & to_string(e_rw) & to_string(e_fw) &
               to_string(e_imm) & " alu=" & alu_op_t'image(e_alu) &
               " br=" & branch_t'image(e_br) & " halt=" & to_string(e_halt)
          severity error;
      end if;
    end procedure;
  begin
    check("ADD",   OPC_ADD,   '1','1','0', ALU_ADD,    BR_NONE, '0');
    check("SUB",   OPC_SUB,   '1','1','0', ALU_SUB,    BR_NONE, '0');
    check("AND",   OPC_AND,   '1','1','0', ALU_AND,    BR_NONE, '0');
    check("OR",    OPC_OR,    '1','1','0', ALU_OR,     BR_NONE, '0');
    check("NOT",   OPC_NOT,   '1','1','0', ALU_NOT,    BR_NONE, '0');
    check("XOR",   OPC_XOR,   '1','1','0', ALU_XOR,    BR_NONE, '0');
    check("SHL",   OPC_SHL,   '1','1','0', ALU_SHL,    BR_NONE, '0');
    check("SHR",   OPC_SHR,   '1','1','0', ALU_SHR,    BR_NONE, '0');
    check("MOV",   OPC_MOV,   '1','0','0', ALU_ADD,    BR_NONE, '0');
    check("LOADI", OPC_LOADI, '1','0','1', ALU_PASS_B, BR_NONE, '0');
    check("BEQ",   OPC_BEQ,   '0','0','0', ALU_SUB,    BR_BEQ,  '0');
    check("BNE",   OPC_BNE,   '0','0','0', ALU_SUB,    BR_BNE,  '0');
    check("JMP",   OPC_JMP,   '0','0','0', ALU_SUB,    BR_JMP,  '0');
    check("HALT",  OPC_HALT,  '0','0','0', ALU_SUB,    BR_NONE, '1');
    check("rsv E", "1110",    '0','0','0', ALU_SUB,    BR_NONE, '0');
    check("rsv F", "1111",    '0','0','0', ALU_SUB,    BR_NONE, '0');

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
