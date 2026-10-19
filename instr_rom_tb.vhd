-- instr_rom_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Reads back a small INIT pattern and checks the HALT fill above it.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity instr_rom_tb is
end entity instr_rom_tb;

architecture sim of instr_rom_tb is
  signal addr : byte_t := (others => '0');
  signal data : word_t;

  constant PROG : rom_t(0 to 3) := (x"9203", x"6440", x"F001", x"C008");
begin

  dut : entity work.instr_rom
    generic map (INIT => PROG)
    port map (addr => addr, data => data);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure expect (name : string; a : natural; w : word_t) is
    begin
      addr <= std_logic_vector(to_unsigned(a, 8));
      wait for 1 ns;
      checks := checks + 1;
      if data /= w then
        errors := errors + 1;
        report "FAIL " & name & " addr=" & integer'image(a) &
               " got=0x" & to_hstring(data) &
               " expected=0x" & to_hstring(w) severity error;
      end if;
    end procedure;
  begin
    expect("word 0",   0, x"9203");
    expect("word 1",   1, x"6440");
    expect("word 2",   2, x"F001");
    expect("word 3",   3, x"C008");
    expect("fill 4",   4, x"F001");   -- above the program: HALT filler
    expect("fill 100", 100, x"F001");
    expect("fill 255", 255, x"F001");
    expect("re-read 0", 0, x"9203");  -- async read is repeatable

    report "instr_rom_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "INSTR ROM TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "INSTR ROM TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
