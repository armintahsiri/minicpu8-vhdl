-- pc.vhd : 8-bit program counter for MiniCPU-8
-- Synchronous active-high reset to 0; en=0 holds (HALT);
-- load=1 takes target, otherwise increments. All modulo 256.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity pc is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    en     : in  std_logic;
    load   : in  std_logic;
    target : in  byte_t;
    q      : out byte_t);
end entity pc;

architecture rtl of pc is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin
  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= (others => '0');
      elsif en = '1' then
        if load = '1' then
          cnt <= unsigned(target);
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;

  q <= std_logic_vector(cnt);
end architecture rtl;
