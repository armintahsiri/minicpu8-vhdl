-- hello_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- CPU-level assertion for programs/hello.asm. Expected UART text is
-- "Hello, MiniCPU-8!\n".
library ieee;
use ieee.std_logic_1164.all;

entity hello_tb is
end entity hello_tb;

architecture sim of hello_tb is
  constant LF : character := character'val(10);
begin
  harness : entity work.uart_demo_tb
    generic map (
      PROGRAM         => work.hello_rom.PROG,
      RAM_INIT        => work.hello_ram.INIT,
      EXPECTED        => "Hello, MiniCPU-8!" & LF,
      CYCLE_BUDGET    => 5000,
      EXPECTED_CYCLES => 1915);
end architecture sim;
