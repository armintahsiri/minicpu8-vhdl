-- minicpu_pkg.vhd : shared types/constants for MiniCPU-8
library ieee;
use ieee.std_logic_1164.all;

package minicpu_pkg is
  -- ALU operation select. An enumeration is self-documenting and
  -- decouples the ALU from the instruction opcode numbering.
  -- 9 values: the 8 "compute" ops + PASS_B pass-through used by LOADI.
  type alu_op_t is (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_NOT, ALU_PASS_B,
                    ALU_XOR, ALU_SHL, ALU_SHR);

  -- Data types
  subtype byte_t  is std_logic_vector(7 downto 0);    -- data path
  subtype word_t  is std_logic_vector(15 downto 0);   -- instruction word
  type rom_t      is array (natural range <>) of word_t;
  type regfile_t  is array (0 to 7) of byte_t;        -- debug view of R0..R7

  -- Branch condition select (control unit -> PC logic)
  type branch_t is (BR_NONE, BR_BEQ, BR_BNE, BR_JMP);

  -- Instruction field positions (see docs/ISA.md)
  -- [15:12]=opcode [11:9]=rd [8:6]=rs [5:3]=rt [2:0]=0 | I-type: [5:0]=imm6
  subtype opcode_t is std_logic_vector(3 downto 0);
  subtype regsel_t is std_logic_vector(2 downto 0);
  subtype imm6_t   is std_logic_vector(5 downto 0);

  constant OPC_ADD    : opcode_t := "0000";
  constant OPC_SUB    : opcode_t := "0001";
  constant OPC_AND    : opcode_t := "0010";
  constant OPC_OR     : opcode_t := "0011";
  constant OPC_NOT    : opcode_t := "0100";
  constant OPC_XOR    : opcode_t := "0101";
  constant OPC_SHL    : opcode_t := "0110";
  constant OPC_SHR    : opcode_t := "0111";
  constant OPC_MOV    : opcode_t := "1000";
  constant OPC_LOADI  : opcode_t := "1001";
  constant OPC_BEQ    : opcode_t := "1010";
  constant OPC_BNE    : opcode_t := "1011";
  constant OPC_JMP    : opcode_t := "1100";
  constant OPC_HALT   : opcode_t := "1101";
  -- "1110"/"1111" reserved, decode as NOP

  constant HALT_WORD  : word_t := x"D000";            -- ROM filler word
end package minicpu_pkg;
