-- cycle_counter.vhd : free-running 8-bit cycle counter for MiniCPU-8
-- Synchronously reset to zero, then increments on every rising clock edge
-- (including while the CPU is halted). Only the low byte is exposed through
-- MMIO address 0xF4; it wraps 0xFF -> 0x00 naturally.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity cycle_counter is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    count : out byte_t);
end entity cycle_counter;

architecture rtl of cycle_counter is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= (others => '0');
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  count <= std_logic_vector(cnt);

end architecture rtl;
