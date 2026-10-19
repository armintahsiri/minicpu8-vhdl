-- flag_reg.vhd : Z/N/C/V flag register for MiniCPU-8
-- Bit order: q(3)=Z, q(2)=N, q(1)=C, q(0)=V. Synchronous write enable,
-- synchronous active-high reset to 0000.
library ieee;
use ieee.std_logic_1164.all;

entity flag_reg is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    en  : in  std_logic;                          -- write enable
    d   : in  std_logic_vector(3 downto 0);       -- Z N C V in
    q   : out std_logic_vector(3 downto 0));      -- Z N C V out
end entity flag_reg;

architecture rtl of flag_reg is
begin
  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        q <= (others => '0');
      elsif en = '1' then
        q <= d;
      end if;
    end if;
  end process;
end architecture rtl;
