-- cycle_counter_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Checks reset-to-zero, increment on every clock, and modulo-256 wrap.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity cycle_counter_tb is
end entity cycle_counter_tb;

architecture sim of cycle_counter_tb is
  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal count : byte_t;
begin

  clk <= not clk after 5 ns;

  dut : entity work.cycle_counter
    port map (clk => clk, rst => rst, count => count);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure expect (name : string; got : natural; exp : natural) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "CYCLE FAIL " & name & " got=" & integer'image(got) &
               " expected=" & integer'image(exp) severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    expect("reset value", to_integer(unsigned(count)), 0);
    rst <= '0';

    for i in 1 to 5 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      expect("increment " & integer'image(i),
             to_integer(unsigned(count)), i);
    end loop;

    -- 250 more edges -> 255, then one more -> 0 (wrap).
    for i in 6 to 255 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    expect("count 255", to_integer(unsigned(count)), 255);
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("wrap to 0", to_integer(unsigned(count)), 0);
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("after wrap", to_integer(unsigned(count)), 1);

    -- Reset in the middle of free running clears it.
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("reset from running", to_integer(unsigned(count)), 0);
    rst <= '0';

    report "cycle_counter_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "CYCLE COUNTER TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "CYCLE COUNTER TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
