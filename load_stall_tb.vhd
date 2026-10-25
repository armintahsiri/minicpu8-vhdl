-- EXPERIMENT: hand-derived checks for synchronous-RAM LOAD timing.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity load_stall_tb is
end entity;

architecture sim of load_stall_tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal halted : std_logic;
  signal pc : byte_t;
  signal flags : std_logic_vector(3 downto 0);
  signal regs : regfile_t;
  signal ram : ram_t;
  signal gpio_out : byte_t;
  signal uart_tx : std_logic;
begin
  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => work.load_stall_demo_rom.PROG,
                 RAM_INIT => work.load_stall_demo_ram.INIT,
                 CLK_FREQ => 1_000_000, BAUD => 100_000,
                 DEBUG => true, LOAD_STALL => true)
    port map (clk => clk, rst => rst, halted => halted, gpio_in => x"A5",
              gpio_out => gpio_out, uart_tx => uart_tx, dbg_pc => pc,
              dbg_flags => flags, dbg_regs => regs, dbg_ram => ram);

  stim : process
    variable cycle : natural := 0;
    variable reset_done : boolean := false;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';

    while halted /= '1' loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      assert cycle <= 20 report "cycle budget exceeded" severity failure;
      wait for 1 ns;
      case cycle is
        when 1 => assert pc = x"01" and regs(1) = x"05" report "cycle 1 LOADI" severity failure;
        when 2 => assert pc = x"02" and regs(5) = x"05" and flags = "0000" report "cycle 2 flags seed" severity failure;
        when 3 => assert pc = x"03" and ram(0) = x"05" report "cycle 3 STORE" severity failure;
        when 4 =>
          assert pc = x"03" and regs(2) = x"00" and flags = "0000"
            report "cycle 4 first RAM LOAD wait" severity failure;
          if not reset_done then
            -- Assert reset during the second LOAD interval, before commit.
            rst <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert pc = x"00" and regs(2) = x"00" and gpio_out = x"00"
              report "reset cancels pending LOAD and resets PC/MMIO" severity failure;
            wait until falling_edge(clk);
            rst <= '0';
            reset_done := true;
            cycle := 0;
          end if;
        when 5 => assert pc = x"04" and regs(2) = x"05" and flags = "0000" report "cycle 5 RAM LOAD commit" severity failure;
        when 6 => assert pc = x"05" and regs(3) = x"F2" report "cycle 6 LOADI GPIO" severity failure;
        when 7 => assert pc = x"06" and gpio_out = x"05" report "cycle 7 STORE GPIO once" severity failure;
        when 8 => assert pc = x"06" and regs(4) = x"00" and flags = "0000" report "cycle 8 first MMIO LOAD wait" severity failure;
        when 9 => assert pc = x"07" and regs(4) = x"05" and flags = "0000" report "cycle 9 MMIO LOAD commit" severity failure;
        when 10 => assert pc = x"08" and regs(6) = x"F4" report "cycle 10 LOADI cycle counter" severity failure;
        when 11 => assert pc = x"08" and regs(7) = x"00" report "cycle 11 first counter LOAD wait" severity failure;
        when 12 => assert pc = x"09" and regs(7) = x"0B" report "cycle 12 counter LOAD commit value" severity failure;
        when others => assert false report "unexpected extra cycle" severity failure;
      end case;
    end loop;

    assert cycle = 12 report "three LOADs add exactly three cycles" severity failure;
    assert pc = x"09" and regs(2) = x"05" and regs(4) = x"05"
      report "final architectural values" severity failure;
    assert gpio_out = x"05" and ram(0) = x"05" and flags = "0000"
      report "STORE effect, RAM and flags" severity failure;
    report "load_stall_tb: 12 cycle checks, 0 errors (EXPERIMENT)" severity note;
    report "LOAD STALL TESTBENCH: ALL TESTS PASSED" severity note;
    finish;
  end process;
end architecture;
