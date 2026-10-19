-- gpio.vhd : 8-bit GPIO output register + 2-flop input synchronizer
-- GPIO_OUT is a normal synchronous register (reset to 0), readable back.
-- GPIO_IN is asynchronous in the FPGA pin domain; it is synchronized by two
-- flops before the CPU can read it. A pin change therefore becomes visible
-- after two rising clock edges. The raw pin is never read directly.
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

entity gpio is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    we       : in  std_logic;             -- write GPIO_OUT
    wdata    : in  byte_t;
    rd_out   : out byte_t;                -- readback of GPIO_OUT
    pin_in   : in  byte_t;                -- raw switches/buttons
    pin_out  : out byte_t;                -- LEDs
    in_sync  : out byte_t);               -- synchronized GPIO_IN
end entity gpio;

architecture rtl of gpio is
  signal out_reg : byte_t := (others => '0');
  signal meta    : byte_t := (others => '0');
  signal sync    : byte_t := (others => '0');
begin

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        out_reg <= (others => '0');
        meta    <= (others => '0');
        sync    <= (others => '0');
      else
        if we = '1' then
          out_reg <= wdata;
        end if;
        -- Two-flop synchronizer. Both flops reset so the first read after
        -- reset is deterministic.
        meta <= pin_in;
        sync <= meta;
      end if;
    end if;
  end process;

  rd_out  <= out_reg;
  pin_out <= out_reg;
  in_sync <= sync;

end architecture rtl;
