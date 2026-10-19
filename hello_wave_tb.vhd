-- hello_wave_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Runs programs/hello.asm only until the first UART byte has been captured,
-- then stops. Used to produce docs/waves/hello_first_byte.vcd without the
-- remaining 17 bytes of the full hello run.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity hello_wave_tb is
end entity hello_wave_tb;

architecture sim of hello_wave_tb is
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal halted   : std_logic;
  signal pc       : byte_t;
  signal flags    : std_logic_vector(3 downto 0);
  signal regs     : regfile_t;
  signal ram      : ram_t;
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_count : natural range 0 to 1;
  signal rx_err   : natural;
  signal done     : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => work.hello_rom.PROG,
                 RAM_INIT => work.hello_ram.INIT,
                 CLK_FREQ => 1_000_000, BAUD => 100_000)
    port map (clk => clk, rst => rst, halted => halted, gpio_in => x"00",
              gpio_out => gpio_out, uart_tx => uart_tx, dbg_pc => pc,
              dbg_flags => flags, dbg_regs => regs, dbg_ram => ram);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => 10, MAX_BYTES => 1)
    port map (clk => clk, rst => rst, serial => uart_tx, data => rx_data,
              count => rx_count, errors => rx_err);

  stim : process
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';
    for i in 1 to 500 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      exit when rx_count = 1;
    end loop;
    assert rx_count = 1 report "WAVE: no UART byte captured" severity failure;
    assert rx_data = x"48" report "WAVE: first hello byte is not 'H'"
      severity failure;
    assert rx_err = 0 report "WAVE: UART framing error" severity failure;
    report "hello_wave_tb: first byte 0x48 captured";
    done <= true;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
