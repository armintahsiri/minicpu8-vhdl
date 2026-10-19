-- control_unit.vhd : combinational decoder for MiniCPU-8 (ISA v2)
-- opcode + extended-function field + jump-group condition code -> controls.
-- See docs/ISA.md for the normative decode table.
--
--   reg_write    : write the writeback value to rd (or R7 for CALL)
--   mem_read     : LOAD is reading the data RAM (also selects WB_MEM)
--   mem_write    : STORE writes the data RAM
--   flag_write   : update Z/N/C/V from the ALU
--   alu_src_imm  : ALU B input = sign-extended imm6 instead of register rt/rd
--   rd2_from_rd  : register port 2 address = rd field [11:9] (BEQ/BNE/STORE)
--   alu_op       : ALU operation select
--   wb_sel       : writeback source: ALU result / RAM data / PC+1 (CALL link)
--   pc_sel       : next-PC source: next / absolute / relative EQ-NE / R7 / hold
--   cond_code    : jump-group condition passed to branch_cond
--   link         : CALL writes PC+1 to R7 (hardware forces the R7 write address)
--   halt         : freeze the PC
-- Reserved function codes and reserved jump-group condition codes decode as
-- complete NOPs (all writes inactive, PC+1).
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

entity control_unit is
  port (
    opcode      : in  opcode_t;
    func        : in  func_t;
    cond_code   : in  cond_code_t;
    reg_write   : out std_logic;
    mem_read    : out std_logic;
    mem_write   : out std_logic;
    flag_write  : out std_logic;
    alu_src_imm : out std_logic;
    rd2_from_rd : out std_logic;
    alu_op      : out alu_op_t;
    wb_sel      : out wb_sel_t;
    pc_sel      : out pc_sel_t;
    cond_out    : out cond_code_t;
    link        : out std_logic;
    halt        : out std_logic);
end entity control_unit;

architecture rtl of control_unit is
begin
  process (all)
  begin
    -- Defaults for every output: no inferred latches.
    reg_write   <= '0';
    mem_read    <= '0';
    mem_write   <= '0';
    flag_write  <= '0';
    alu_src_imm <= '0';
    rd2_from_rd <= '0';
    alu_op      <= ALU_ADD;          -- don't care when nothing is written
    wb_sel      <= WB_ALU;
    pc_sel      <= PC_NEXT;
    cond_out    <= COND_JMP;         -- always, when a PC_ABS branch is used
    link        <= '0';
    halt        <= '0';

    case opcode is
      -- ---- R-type ALU operations ---------------------------------------
      when OPC_ADD  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_ADD;
      when OPC_SUB  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SUB;
      when OPC_AND  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_AND;
      when OPC_OR   => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_OR;
      when OPC_NOT  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_NOT;
      when OPC_XOR  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_XOR;
      when OPC_SHL  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SHL;
      when OPC_SHR  => reg_write <= '1'; flag_write <= '1'; alu_op <= ALU_SHR;

      -- ---- memory --------------------------------------------------------
      when OPC_LOAD =>
        reg_write <= '1'; mem_read <= '1'; alu_src_imm <= '1';
        alu_op <= ALU_ADD; wb_sel <= WB_MEM;
      when OPC_STORE =>
        mem_write <= '1'; alu_src_imm <= '1'; rd2_from_rd <= '1';
        alu_op <= ALU_ADD;

      -- ---- immediates ----------------------------------------------------
      when OPC_LOADI =>
        reg_write <= '1'; alu_src_imm <= '1'; alu_op <= ALU_PASS_B;
      when OPC_ADDI =>
        reg_write <= '1'; flag_write <= '1'; alu_src_imm <= '1';
        alu_op <= ALU_ADD;

      -- ---- Phase 1 branches (dedicated comparator, PC-relative) ---------
      when OPC_BEQ =>
        pc_sel <= PC_REL_EQ; rd2_from_rd <= '1';
      when OPC_BNE =>
        pc_sel <= PC_REL_NE; rd2_from_rd <= '1';

      -- ---- jump group: absolute target in bits 7:0 -----------------------
      when OPC_JMP =>
        case cond_code is
          when COND_JMP => pc_sel <= PC_ABS; cond_out <= COND_JMP;
          when COND_BZ  => pc_sel <= PC_ABS; cond_out <= COND_BZ;
          when COND_BNZ => pc_sel <= PC_ABS; cond_out <= COND_BNZ;
          when COND_BCS => pc_sel <= PC_ABS; cond_out <= COND_BCS;
          when COND_BCC => pc_sel <= PC_ABS; cond_out <= COND_BCC;
          when COND_BN  => pc_sel <= PC_ABS; cond_out <= COND_BN;
          when COND_BNN => pc_sel <= PC_ABS; cond_out <= COND_BNN;
          when COND_BLT => pc_sel <= PC_ABS; cond_out <= COND_BLT;
          when COND_BGE => pc_sel <= PC_ABS; cond_out <= COND_BGE;
          when COND_CALL =>
            pc_sel <= PC_ABS; cond_out <= COND_JMP;
            link <= '1'; reg_write <= '1'; wb_sel <= WB_PC1;
          when others => null;      -- 0x9..0xE reserved: NOP
        end case;

      -- ---- extended group -----------------------------------------------
      when OPC_EXT =>
        case func is
          when FUNC_NOP  => null;
          when FUNC_HALT => halt <= '1'; pc_sel <= PC_HOLD;
          when FUNC_RET  => pc_sel <= PC_R7;
          when FUNC_CMP  => flag_write <= '1'; alu_op <= ALU_SUB;
          when others    => null;    -- 0x4..0x7 reserved: NOP
        end case;

      when others => null;
    end case;
  end process;
end architecture rtl;
