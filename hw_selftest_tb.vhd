-- Simulation assertion for the hardware bring-up GPIO/UART heartbeat program.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity hw_selftest_tb is
  generic (LOAD_STALL : boolean := false);
end entity hw_selftest_tb;

architecture sim of hw_selftest_tb is
  constant MAX_BYTES : natural := 3;
  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal halted    : std_logic;
  signal gpio_out  : byte_t;
  signal uart_tx   : std_logic;
  signal pc        : byte_t;
  signal flags     : std_logic_vector(3 downto 0);
  signal regs      : regfile_t;
  signal ram       : ram_t;
  signal rx_data   : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  signal rx_count  : natural range 0 to MAX_BYTES;
  signal rx_errors : natural;
begin
  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => work.hw_selftest_rom.PROG,
                 RAM_INIT => work.hw_selftest_ram.INIT,
                 CLK_FREQ => 1_000_000, BAUD => 100_000,
                 LOAD_STALL => LOAD_STALL)
    port map (clk => clk, rst => rst, halted => halted,
              gpio_in => x"00", gpio_out => gpio_out, uart_tx => uart_tx,
              dbg_pc => pc, dbg_flags => flags, dbg_regs => regs,
              dbg_ram => ram);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => 10, MAX_BYTES => MAX_BYTES)
    port map (clk => clk, rst => rst, serial => uart_tx, data => rx_data,
              count => rx_count, errors => rx_errors);

  stim : process
    variable cycles : natural := 0;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';

    while rx_count < MAX_BYTES or gpio_out /= x"0F" or regs(3) /= x"10" loop
      wait until rising_edge(clk);
      wait for 1 ns;
      cycles := cycles + 1;
      assert cycles < 2000 report "hardware self-test timed out" severity failure;
    end loop;
    assert rx_data(7 downto 0) = x"4F" report "heartbeat byte 0 is not O" severity failure;
    assert rx_data(15 downto 8) = x"4B" report "heartbeat byte 1 is not K" severity failure;
    assert rx_data(23 downto 16) = x"0A" report "heartbeat byte 2 is not newline" severity failure;
    assert rx_count = 3 report "heartbeat byte count mismatch" severity failure;
    assert rx_errors = 0 report "UART framing error in heartbeat" severity failure;
    assert gpio_out = x"0F" report "GPIO counter pattern did not reach 0x0F" severity failure;
    assert regs(3) = x"10" report "GPIO counter did not complete 16 steps" severity failure;
    report "hw_selftest_tb: PASS, GPIO=0x0F, UART=OK\n" severity note;
    report "HARDWARE SELF-TEST TESTBENCH: ALL TESTS PASSED" severity note;
    finish;
    wait;
  end process;

  watchdog : process
  begin
    wait for 1 ms;
    report "HARDWARE SELF-TEST TESTBENCH: GLOBAL WATCHDOG TIMEOUT"
      severity failure;
    wait;
  end process;
end architecture sim;
