-- Directed CPU regression for 8-bit effective-address wrap at RAM 0xFF -> 0.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity ram_wrap_tb is
end entity ram_wrap_tb;

architecture sim of ram_wrap_tb is
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal halted   : std_logic;
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;
  signal pc       : byte_t;
  signal flags    : std_logic_vector(3 downto 0);
  signal regs     : regfile_t;
  signal ram      : ram_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => work.ram_wrap_rom.PROG,
                 RAM_INIT => work.ram_wrap_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted,
              gpio_in => x"00", gpio_out => gpio_out, uart_tx => uart_tx,
              dbg_pc => pc, dbg_flags => flags, dbg_regs => regs,
              dbg_ram => ram);

  stim : process
    variable cycles : natural := 0;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';

    while halted /= '1' loop
      wait until rising_edge(clk);
      wait for 1 ns;
      cycles := cycles + 1;
      assert cycles < 20 report "RAM wrap program timed out" severity failure;
    end loop;

    assert regs(1) = x"FF" report "r1 did not hold 0xFF" severity failure;
    assert regs(2) = x"05" report "r2 did not hold 0x05" severity failure;
    assert regs(3) = x"05" report "LOAD at wrapped address missed store" severity failure;
    assert ram(0) = x"05" report "STORE at 0xFF + 1 did not wrap to RAM[0]" severity failure;
    report "ram_wrap_tb: PASS, effective address 0xFF+1 -> 0x00" severity note;
    report "RAM WRAP TESTBENCH: ALL TESTS PASSED" severity note;
    finish;
    wait;
  end process;

  watchdog : process
  begin
    wait for 1 us;
    report "RAM WRAP TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;
end architecture sim;
