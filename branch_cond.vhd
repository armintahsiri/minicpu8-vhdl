-- branch_cond.vhd : combinational jump-group condition decoder for MiniCPU-8
-- Inputs: flags = Z N C V (bit 3 = Z, bit 2 = N, bit 1 = C, bit 0 = V)
--         cond  = 4-bit condition/operation code from the jump-group
-- Output: taken = '1' when the branch/call is taken.
-- Codes 0x9..0xE are reserved and decode as not-taken (NOP).
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

entity branch_cond is
  port (
    flags : in  std_logic_vector(3 downto 0);  -- Z N C V
    cond  : in  cond_code_t;
    taken : out std_logic);
end entity branch_cond;

architecture rtl of branch_cond is
  signal z, n, c, v : std_logic;
begin
  z <= flags(3);
  n <= flags(2);
  c <= flags(1);
  v <= flags(0);

  -- Every condition code appears explicitly; reserved codes are not-taken.
  -- Equations (see docs/ISA.md):
  --   BHS/BCS = C,  BLO/BCC = not C
  --   BLT = N xor V, BGE = not (N xor V)
  decode_p : process (all) is
  begin
    taken <= '0';                       -- default: reserved / never
    case cond is
      when COND_JMP => taken <= '1';    -- JMP (always)
      when COND_BZ  => taken <= z;
      when COND_BNZ => taken <= not z;
      when COND_BCS => taken <= c;      -- unsigned >=
      when COND_BCC => taken <= not c;  -- unsigned <
      when COND_BN  => taken <= n;
      when COND_BNN => taken <= not n;
      when COND_BLT => taken <= n xor v;
      when COND_BGE => taken <= not (n xor v);
      when COND_CALL => taken <= '1';   -- CALL (always)
      when others   => taken <= '0';    -- 0x9..0xE reserved
    end case;
  end process;
end architecture rtl;
