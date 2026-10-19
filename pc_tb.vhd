-- pc_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Reset to 0, increment sequence, load, hold on en=0, 0xFF wrap to 0.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity pc_tb is
end entity pc_tb;

architecture sim of pc_tb is
  signal clk : std_logic := '0';
  signal rst, en, load : std_logic := '0';
  signal target : byte_t := (others => '0');
  signal q : byte_t;
begin

  clk <= not clk after 5 ns;

  dut : entity work.pc
    port map (clk => clk, rst => rst, en => en, load => load,
              target => target, q => q);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure expect (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;

    -- Called while the process is AT a falling edge: apply controls now,
    -- then pass exactly one rising edge with these controls.
    procedure step (i_en, i_load : std_logic; i_target : byte_t) is
    begin
      en <= i_en; load <= i_load; target <= i_target;
      wait until falling_edge(clk);
    end procedure;
  begin
    -- reset (after preloading a non-zero value to prove reset works)
    wait until falling_edge(clk);          -- t=10
    rst <= '0'; en <= '1'; load <= '1'; target <= x"77";
    wait until falling_edge(clk);          -- t=20: rising at 15 loaded 0x77
    expect("preload 77", q, x"77");
    wait until falling_edge(clk);          -- t=30 (controls held: another 77 load)
    rst <= '1';
    wait until falling_edge(clk);          -- t=40: rising at 35 applied reset
    rst <= '0'; en <= '0';
    expect("reset to 0x00", q, x"00");

    -- increments 1,2,3
    step('1', '0', x"00"); expect("inc to 01", q, x"01");
    step('1', '0', x"00"); expect("inc to 02", q, x"02");
    step('1', '0', x"00"); expect("inc to 03", q, x"03");

    -- load 0x42, then increment after load
    step('1', '1', x"42"); expect("load 42", q, x"42");
    step('1', '0', x"00"); expect("inc after load", q, x"43");

    -- hold on en=0 even with load=1
    step('0', '1', x"00"); expect("hold when en=0", q, x"43");

    -- load 0xFF, then wrap to 0
    step('1', '1', x"FF"); expect("load FF", q, x"FF");
    step('1', '0', x"00"); expect("wrap FF->00", q, x"00");

    report "pc_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "PC TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "PC TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
