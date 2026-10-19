-- primes_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- CPU-level assertion for programs/primes.asm. Captured UART bytes are compared
-- with the full expected output below (newline appended as character'val(10)).
library ieee;
use ieee.std_logic_1164.all;

entity primes_tb is
end entity primes_tb;

architecture sim of primes_tb is
  constant LF : character := character'val(10);
begin
  harness : entity work.uart_demo_tb
    generic map (
      PROGRAM         => work.primes_rom.PROG,
      RAM_INIT        => work.primes_ram.INIT,
      EXPECTED        => "2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97 101 103 107 109 113 127 131 137 139 149 151 157 163 167 173 179 181 191 193 197 199 211 223 227 229 233 239 241 251 " & LF,
      CYCLE_BUDGET    => 500000,
      EXPECTED_CYCLES => 276236);
end architecture sim;
