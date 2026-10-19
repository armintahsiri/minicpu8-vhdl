-- flag_reg_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Reset clears, en=0 holds, en=1 loads new ZNCV each cycle.
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity flag_reg_tb is
end entity flag_reg_tb;

architecture sim of flag_reg_tb is
  signal clk : std_logic := '0';
  signal rst, en : std_logic := '0';
  signal d, q : std_logic_vector(3 downto 0) := (others => '0');
begin

  clk <= not clk after 5 ns;

  dut : entity work.flag_reg
    port map (clk => clk, rst => rst, en => en, d => d, q => q);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure expect (name : string; got, exp : std_logic_vector(3 downto 0)) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " got=" & to_string(got) &
               " expected=" & to_string(exp) severity error;
      end if;
    end procedure;
  begin
    -- load a pattern, then reset must clear it
    wait until falling_edge(clk);
    rst <= '0'; en <= '1'; d <= "1010";
    wait until falling_edge(clk);          -- rising edge: q = 1010
    expect("loaded ZNCV=1010", q, "1010");

    wait until falling_edge(clk);
    rst <= '1'; en <= '0';
    wait until falling_edge(clk);          -- rising edge: reset applied
    rst <= '0';
    expect("reset clears to 0000", q, "0000");

    -- en=0: d must be ignored
    wait until falling_edge(clk);
    en <= '0'; d <= "0110";
    wait until falling_edge(clk);          -- rising edge with en=0: hold
    expect("hold when en=0", q, "0000");

    -- en=1: follow d each cycle
    wait until falling_edge(clk);
    en <= '1'; d <= "0001";
    wait until falling_edge(clk);
    expect("load 0001", q, "0001");
    wait until falling_edge(clk);
    d <= "1110";
    wait until falling_edge(clk);
    expect("load 1110", q, "1110");

    -- reset dominates en
    wait until falling_edge(clk);
    rst <= '1'; en <= '1'; d <= "0101";
    wait until falling_edge(clk);
    rst <= '0'; en <= '0';
    expect("reset wins over en", q, "0000");

    report "flag_reg_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "FLAG REG TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "FLAG REG TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
