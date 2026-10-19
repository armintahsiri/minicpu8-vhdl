-- minicpu_pkg.vhd : shared types/constants for MiniCPU-8 (ISA v2)
library ieee;
use ieee.std_logic_1164.all;

package minicpu_pkg is
  -- ALU operation select. An enumeration is self-documenting and
  -- decouples the ALU from the instruction opcode numbering.
  type alu_op_t is (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_NOT, ALU_PASS_B,
                    ALU_XOR, ALU_SHL, ALU_SHR);

  -- Writeback source select (ALU result / data RAM / PC+1 for CALL).
  type wb_sel_t is (WB_ALU, WB_MEM, WB_PC1);

  -- Next-PC selection.  BEQ/BNE keep their Phase 1 dedicated-comparator
  -- behaviour; PC_ABS uses the jump-group condition code and an absolute
  -- target; PC_R7 is RET; PC_HOLD is HALT.
  type pc_sel_t is (PC_NEXT, PC_ABS, PC_REL_EQ, PC_REL_NE, PC_R7, PC_HOLD);

  -- Data types
  subtype byte_t  is std_logic_vector(7 downto 0);    -- data path
  subtype word_t  is std_logic_vector(15 downto 0);   -- instruction word
  type rom_t      is array (natural range <>) of word_t;
  type ram_init_t is array (natural range <>) of byte_t;
  type ram_t      is array (0 to 255) of byte_t;       -- debug view of RAM
  type regfile_t  is array (0 to 7) of byte_t;        -- debug view of R0..R7

  -- Instruction field positions (see docs/ISA.md)
  -- R/X: [15:12]=opcode [11:9]=rd [8:6]=rs [5:3]=rt [2:0]=0/func
  -- I:   [15:12]=opcode [11:9]=rd [8:6]=rs [5:0]=imm6
  -- J:   [15:12]=opcode [11:8]=cond [7:0]=target
  subtype opcode_t    is std_logic_vector(3 downto 0);
  subtype regsel_t    is std_logic_vector(2 downto 0);
  subtype imm6_t      is std_logic_vector(5 downto 0);
  subtype func_t      is std_logic_vector(2 downto 0);
  subtype cond_code_t is std_logic_vector(3 downto 0);

  -- Opcodes (all 16 are assigned in v2)
  constant OPC_ADD    : opcode_t := "0000";
  constant OPC_SUB    : opcode_t := "0001";
  constant OPC_AND    : opcode_t := "0010";
  constant OPC_OR     : opcode_t := "0011";
  constant OPC_NOT    : opcode_t := "0100";
  constant OPC_XOR    : opcode_t := "0101";
  constant OPC_SHL    : opcode_t := "0110";
  constant OPC_SHR    : opcode_t := "0111";
  constant OPC_LOAD   : opcode_t := "1000";
  constant OPC_LOADI  : opcode_t := "1001";
  constant OPC_BEQ    : opcode_t := "1010";
  constant OPC_BNE    : opcode_t := "1011";
  constant OPC_JMP    : opcode_t := "1100";   -- jump group
  constant OPC_STORE  : opcode_t := "1101";
  constant OPC_ADDI   : opcode_t := "1110";
  constant OPC_EXT    : opcode_t := "1111";   -- extended group

  -- Extended-group function codes (opcode 0xF, bits 2:0)
  constant FUNC_NOP  : func_t := "000";
  constant FUNC_HALT : func_t := "001";
  constant FUNC_RET  : func_t := "010";
  constant FUNC_CMP  : func_t := "011";
  -- "100".."111" reserved, decode as NOP

  -- Jump-group condition/operation codes (opcode 0xC, bits 11:8)
  constant COND_JMP : cond_code_t := "0000";
  constant COND_BZ  : cond_code_t := "0001";
  constant COND_BNZ : cond_code_t := "0010";
  constant COND_BCS : cond_code_t := "0011";  -- alias BHS (unsigned >=)
  constant COND_BCC : cond_code_t := "0100";  -- alias BLO (unsigned <)
  constant COND_BN  : cond_code_t := "0101";
  constant COND_BNN : cond_code_t := "0110";
  constant COND_BLT : cond_code_t := "0111";
  constant COND_BGE : cond_code_t := "1000";
  -- "1001".."1110" reserved, decode as NOP
  constant COND_CALL : cond_code_t := "1111";

  constant NOP_WORD  : word_t := x"F000";     -- extended function 0
  constant HALT_WORD : word_t := x"F001";     -- extended function 1 (ROM filler)

  -- Memory map (Phase 3 MMIO).  Data RAM is 0x00..0xEF; 0xF0..0xFF is the
  -- I/O region and is decoded by cpu_top/mmio, never written into data_ram.
  -- See docs/ISA.md section 8.
  constant RAM_LAST       : byte_t := x"EF";
  constant IO_BASE        : byte_t := x"F0";
  constant IO_UART_TX     : byte_t := x"F0";  -- write: transmit byte
  constant IO_UART_STATUS : byte_t := x"F1";  -- read: bit0 = tx_busy
  constant IO_GPIO_OUT    : byte_t := x"F2";  -- write/read: LED register
  constant IO_GPIO_IN     : byte_t := x"F3";  -- read: synchronized inputs
  constant IO_CYCLE_LO    : byte_t := x"F4";  -- read: free-running counter
  constant IO_RESERVED_LO : byte_t := x"F5";
  constant IO_RESERVED_HI : byte_t := x"FF";
end package minicpu_pkg;
