-- fibonacci_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- CPU-level assertion for programs/fibonacci.asm. Captured UART bytes are compared
-- with the full expected output below (newline appended as character'val(10)).
library ieee;
use ieee.std_logic_1164.all;

entity fibonacci_tb is
end entity fibonacci_tb;

architecture sim of fibonacci_tb is
  constant LF : character := character'val(10);
begin
  harness : entity work.uart_demo_tb
    generic map (
      PROGRAM         => work.fibonacci_rom.PROG,
      RAM_INIT        => work.fibonacci_ram.INIT,
      EXPECTED        => "0 1 1 2 3 5 8 13 21 34 55 89 144 233 " & LF,
      CYCLE_BUDGET    => 8000,
      EXPECTED_CYCLES => 4008);
end architecture sim;
