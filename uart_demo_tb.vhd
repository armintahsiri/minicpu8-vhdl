-- uart_demo_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Reusable CPU-level runner for the UART demo programs. It instantiates one
-- cpu_top, captures the serial line with an independent receiver, counts
-- cycles, and compares the received bytes with EXPECTED. Wrapper testbenches
-- (hello_tb, fibonacci_tb, primes_tb) supply PROGRAM/RAM_INIT/EXPECTED.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity uart_demo_tb is
  generic (
    PROGRAM         : rom_t;
    RAM_INIT        : ram_init_t;
    EXPECTED        : string;
    CYCLE_BUDGET    : natural := 10000;
    EXPECTED_CYCLES : natural := 0);
end entity uart_demo_tb;

architecture sim of uart_demo_tb is
  constant CLK_PERIOD   : time    := 10 ns;
  constant CLKS_PER_BIT : natural := 10;
  constant BIT_TIME     : time    := CLK_PERIOD * CLKS_PER_BIT;
  constant NBYTES       : natural := EXPECTED'length;

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal halted   : std_logic;
  signal pc       : byte_t;
  signal flags    : std_logic_vector(3 downto 0);
  signal regs     : regfile_t;
  signal ram      : ram_t;
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;

  signal rx_data   : std_logic_vector(NBYTES * 8 - 1 downto 0);
  signal rx_count  : natural range 0 to NBYTES;
  signal rx_errors : natural;

  function captured (v : std_logic_vector) return string is
    variable s : string(1 to NBYTES);
  begin
    for i in 0 to NBYTES - 1 loop
      s(i + 1) := character'val(
        to_integer(unsigned(v(i * 8 + 7 downto i * 8))));
    end loop;
    return s;
  end function;
begin

  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.cpu_top
    generic map (PROGRAM => PROGRAM, RAM_INIT => RAM_INIT,
                 CLK_FREQ => 1_000_000, BAUD => 100_000)
    port map (clk => clk, rst => rst, halted => halted, gpio_in => x"00",
              gpio_out => gpio_out, uart_tx => uart_tx, dbg_pc => pc,
              dbg_flags => flags, dbg_regs => regs, dbg_ram => ram);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => CLKS_PER_BIT, MAX_BYTES => NBYTES)
    port map (clk => clk, rst => rst, serial => uart_tx, data => rx_data,
              count => rx_count, errors => rx_errors);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : natural := 0;

    procedure expect (name : string; cond : boolean) is
    begin
      checks := checks + 1;
      if not cond then
        errors := errors + 1;
        report "DEMO FAIL: " & name severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';

    while halted /= '1' loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      if cycles > CYCLE_BUDGET then
        report "DEMO: CYCLE BUDGET EXCEEDED (" &
               integer'image(CYCLE_BUDGET) & ")" severity failure;
      end if;
      wait for 1 ns;
    end loop;
    wait for 1 ns;

    -- The programs poll UART_STATUS before halting, so the last stop bit is
    -- already complete. A short drain keeps the check robust.
    wait for 2 * BIT_TIME;
    wait for 1 ns;

    expect("halted", halted = '1');
    expect("cycle count", cycles = EXPECTED_CYCLES);
    expect("received byte count", rx_count = NBYTES);
    expect("no framing errors", rx_errors = 0);
    for i in 0 to NBYTES - 1 loop
      expect("byte " & integer'image(i),
             rx_data(i * 8 + 7 downto i * 8) =
             std_logic_vector(to_unsigned(character'pos(EXPECTED(i + 1)), 8)));
    end loop;

    report "uart_demo_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors, " & integer'image(cycles) &
           " cycles";
    report "DEMO: cycles=" & integer'image(cycles) &
           " expected=" & integer'image(EXPECTED_CYCLES) &
           " bytes=" & integer'image(rx_count) &
           " errors=" & integer'image(rx_errors);
    report "DEMO CAPTURED=""" & captured(rx_data) & """";
    report "DEMO EXPECTED=""" & EXPECTED & """";
    report "DEMO final pc=0x" & to_hstring(pc) &
           " flags=" & to_hstring(flags);

    if errors = 0 then
      report "UART DEMO TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "UART DEMO TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 20 ms;
    report "UART DEMO TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

end architecture sim;
