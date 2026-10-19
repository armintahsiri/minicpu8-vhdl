-- control_unit.vhd : combinational decoder for MiniCPU-8
-- opcode -> control signals. See docs/ISA.md for the full decode table.
--   reg_write  : write ALU result to rd
--   flag_write : update Z/N/C/V from the ALU
--   alu_src_imm: ALU B input = sign-extended imm6 instead of register rt/rd
--   alu_op     : ALU operation select
--   branch     : PC source (BR_NONE = PC+1)
--   halt       : freeze the PC
-- Reserved opcodes decode to all-inactive (NOP).
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

entity control_unit is
  port (
    opcode     : in  opcode_t;
    reg_write  : out std_logic;
    flag_write : out std_logic;
    alu_src_imm: out std_logic;
    alu_op     : out alu_op_t;
    branch     : out branch_t;
    halt       : out std_logic);
end entity control_unit;

architecture rtl of control_unit is
begin

  process (opcode)
  begin
    -- defaults for every output: no inferred latches
    reg_write   <= '0';
    flag_write  <= '0';
    alu_src_imm <= '0';
    alu_op      <= ALU_SUB;   -- don't care when nothing is written
    branch      <= BR_NONE;
    halt        <= '0';

    case opcode is
      when OPC_ADD   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_ADD;
      when OPC_SUB   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SUB;
      when OPC_AND   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_AND;
      when OPC_OR    => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_OR;
      when OPC_NOT   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_NOT;
      when OPC_XOR   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_XOR;
      when OPC_SHL   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SHL;
      when OPC_SHR   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SHR;
      -- MOV rd,rs == ADD rd,rs,R0 but must not touch the flags
      when OPC_MOV   => reg_write <= '1'; alu_op <= ALU_ADD;
      when OPC_LOADI => reg_write <= '1'; alu_src_imm <= '1'; alu_op <= ALU_PASS_B;
      when OPC_BEQ   => branch <= BR_BEQ;
      when OPC_BNE   => branch <= BR_BNE;
      when OPC_JMP   => branch <= BR_JMP;
      when OPC_HALT  => halt <= '1';
      when others    => null;   -- reserved: NOP
    end case;
  end process;

end architecture rtl;
