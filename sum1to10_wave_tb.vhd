-- sum1to10_wave_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Minimal CPU run used to produce docs/waves/sum1to10.vcd. It intentionally
-- contains one DUT (not the eight-program cpu_tb) so the waveform is readable.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity sum1to10_wave_tb is
end entity sum1to10_wave_tb;

architecture sim of sum1to10_wave_tb is
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal halted   : std_logic;
  signal pc       : byte_t;
  signal flags    : std_logic_vector(3 downto 0);
  signal regs     : regfile_t;
  signal ram      : ram_t;
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;
  signal done     : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => work.sum1to10_rom.PROG,
                 RAM_INIT => work.sum1to10_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted, gpio_in => x"00",
              gpio_out => gpio_out, uart_tx => uart_tx, dbg_pc => pc,
              dbg_flags => flags, dbg_regs => regs, dbg_ram => ram);

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
      cycles := cycles + 1;
      wait for 1 ns;
      if cycles > 100 then
        report "WAVE: sum1to10 timeout" severity failure;
      end if;
    end loop;
    wait for 1 ns;
    assert regs(1) = x"37" and regs(2) = x"0B"
      report "WAVE: sum1to10 wrong result" severity failure;
    report "sum1to10_wave_tb: " & integer'image(cycles) & " cycles";
    done <= true;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
