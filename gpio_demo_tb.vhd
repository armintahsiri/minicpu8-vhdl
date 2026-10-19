-- gpio_demo_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- CPU-level assertion for programs/gpio_demo.asm. GPIO_IN is driven with
-- 0xA5; the program inverts it and writes 0x5A to GPIO_OUT. Two NOPs at the
-- start let the two-flop input synchronizer settle before the first READ.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity gpio_demo_tb is
end entity gpio_demo_tb;

architecture sim of gpio_demo_tb is
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal halted   : std_logic;
  signal pc       : byte_t;
  signal flags    : std_logic_vector(3 downto 0);
  signal regs     : regfile_t;
  signal ram      : ram_t;
  signal gpio_in  : byte_t := x"A5";
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;

  constant MAX_CYCLES : natural := 20;
  signal done : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => work.gpio_demo_rom.PROG,
                 RAM_INIT => work.gpio_demo_ram.INIT,
                 CLK_FREQ => 1_000_000, BAUD => 100_000)
    port map (clk => clk, rst => rst, halted => halted, gpio_in => gpio_in,
              gpio_out => gpio_out, uart_tx => uart_tx, dbg_pc => pc,
              dbg_flags => flags, dbg_regs => regs, dbg_ram => ram);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : natural := 0;

    procedure expect (name : string; cond : boolean) is
    begin
      checks := checks + 1;
      if not cond then
        errors := errors + 1;
        report "GPIO DEMO FAIL: " & name severity error;
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
      if cycles > MAX_CYCLES then
        report "GPIO DEMO: CYCLE BUDGET EXCEEDED" severity failure;
      end if;
      wait for 1 ns;
    end loop;
    wait for 1 ns;

    expect("halted", halted = '1');
    expect("cycle count 6", cycles = 6);
    expect("PC 6", pc = x"06");
    expect("r1 = GPIO_IN 0xA5", regs(1) = x"A5");
    expect("r2 = inverted 0x5A", regs(2) = x"5A");
    expect("r3 = readback 0x5A", regs(3) = x"5A");
    expect("GPIO_OUT = 0x5A", gpio_out = x"5A");
    expect("UART idle (not used)", uart_tx = '1');

    report "gpio_demo_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors, " & integer'image(cycles) &
           " cycles";
    if errors = 0 then
      report "GPIO DEMO TESTBENCH: ALL TESTS PASSED";
      done <= true;
    else
      report "GPIO DEMO TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 100 us;
    report "GPIO DEMO TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
