-- control_unit_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Exhaustive decode assertions: every opcode is checked, and every control
-- output is compared.  In particular:
--   * MOV is ADD with rt = R0 (the rt field is zero; the assembler guarantees
--     this) and FlagWrite = 0, so it writes rd but not the flags.
--   * LOADI uses PASS_B with ALUSrc = imm6 and FlagWrite = 0.
--   * reserved opcodes decode to a complete NOP (PC+1, no writes).
-- The testbench also sanity-checks the two instruction encodings that make the
-- MOV/LOADI control behaviour meaningful.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity control_unit_tb is
end entity control_unit_tb;

architecture sim of control_unit_tb is
  constant MOV_WORD   : word_t := x"8700";   -- mov r3, r4
  constant LOADI_WORD : word_t := x"9205";   -- loadi r1, 5
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
    -- Field-layout sanity checks for the two special cases.  MOV rd,rs is
    -- encoded as ADD rd,rs,R0, hence bits [5:3] must be 000.  LOADI uses the
    -- immediate in bits [5:0] and no rt field.
    checks := checks + 1;
    if (MOV_WORD(15 downto 12) /= OPC_MOV) or (MOV_WORD(5 downto 3) /= "000") then
      errors := errors + 1;
      report "FAIL MOV encoding must be opcode 8 with rt=R0" severity error;
    end if;
    checks := checks + 1;
    if (LOADI_WORD(15 downto 12) /= OPC_LOADI) or (LOADI_WORD(5 downto 0) /= "000101") then
      errors := errors + 1;
      report "FAIL LOADI encoding must be opcode 9 with a 6-bit immediate" severity error;
    end if;

    check("ADD",   OPC_ADD,   '1','1','0', ALU_ADD,    BR_NONE, '0');
    check("SUB",   OPC_SUB,   '1','1','0', ALU_SUB,    BR_NONE, '0');
    check("AND",   OPC_AND,   '1','1','0', ALU_AND,    BR_NONE, '0');
    check("OR",    OPC_OR,    '1','1','0', ALU_OR,     BR_NONE, '0');
    check("NOT",   OPC_NOT,   '1','1','0', ALU_NOT,    BR_NONE, '0');
    check("XOR",   OPC_XOR,   '1','1','0', ALU_XOR,    BR_NONE, '0');
    check("SHL",   OPC_SHL,   '1','1','0', ALU_SHL,    BR_NONE, '0');
    check("SHR",   OPC_SHR,   '1','1','0', ALU_SHR,    BR_NONE, '0');
    -- MOV is ADD with rt=R0; it writes rd but never the flags.
    check("MOV (ADD rt=R0, no flags)", OPC_MOV, '1','0','0',
          ALU_ADD, BR_NONE, '0');
    -- LOADI is PASS_B of the sign-extended immediate; no flags.
    check("LOADI (PASS_B, no flags)", OPC_LOADI, '1','0','1',
          ALU_PASS_B, BR_NONE, '0');
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
