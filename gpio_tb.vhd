-- gpio_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Checks GPIO_OUT reset/write/readback/pin drive, write-enable gating, and
-- the documented two-flop delay of the GPIO_IN synchronizer.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity gpio_tb is
end entity gpio_tb;

architecture sim of gpio_tb is
  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal we      : std_logic := '0';
  signal wdata   : byte_t := (others => '0');
  signal rd_out  : byte_t;
  signal pin_in  : byte_t := (others => '0');
  signal pin_out : byte_t;
  signal in_sync : byte_t;
begin

  clk <= not clk after 5 ns;

  dut : entity work.gpio
    port map (clk => clk, rst => rst, we => we, wdata => wdata,
              rd_out => rd_out, pin_in => pin_in, pin_out => pin_out,
              in_sync => in_sync);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure expect (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "GPIO FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    expect("reset out", rd_out, x"00");
    expect("reset pin_out", pin_out, x"00");
    expect("reset in_sync", in_sync, x"00");
    rst <= '0';

    -- GPIO_OUT write.
    wait until falling_edge(clk);
    wdata <= x"A5";
    we    <= '1';
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    we <= '0';
    wait for 1 ns;
    expect("write readback", rd_out, x"A5");
    expect("write pin_out", pin_out, x"A5");

    -- we='0' must not change the register, even with different wdata.
    wait until falling_edge(clk);
    wdata <= x"5A";
    we    <= '0';
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    wait for 1 ns;
    expect("we=0 holds", rd_out, x"A5");

    -- Input synchronizer: first edge captures into meta, second into sync.
    pin_in <= x"C3";
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("input not visible after one edge", in_sync, x"00");
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("input visible after two edges", in_sync, x"C3");

    -- Reset clears both the output register and the synchronizer.
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("reset clears out", rd_out, x"00");
    expect("reset clears pin_out", pin_out, x"00");
    expect("reset clears in_sync", in_sync, x"00");
    rst <= '0';

    report "gpio_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "GPIO TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "GPIO TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
