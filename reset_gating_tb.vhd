-- reset_gating_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Proves that synchronous reset suppresses architectural writes, not only the
-- PC: instruction 0 would write R1 and instruction 1 would write RAM[3], but
-- neither may happen while rst='1'.  RAM[3] is initialized to 0xAA.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity reset_gating_tb is
end entity reset_gating_tb;

architecture sim of reset_gating_tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal halted : std_logic;
  signal pc : byte_t;
  signal flags : std_logic_vector(3 downto 0);
  signal regs : regfile_t;
  signal ram : ram_t;

  constant PROG : rom_t(0 to 2) := (
    0 => x"9205",   -- loadi r1, 5
    1 => x"D203",   -- store r1, [r0+3]
    2 => x"F001");  -- halt
  constant RAM_INIT : ram_init_t(0 to 3) :=
    (0 => x"00", 1 => x"00", 2 => x"00", 3 => x"AA");

  signal done : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => PROG, RAM_INIT => RAM_INIT)
    port map (clk => clk, rst => rst, halted => halted,
              dbg_pc => pc, dbg_flags => flags, dbg_regs => regs,
              dbg_ram => ram);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : natural := 0;

    procedure expect_byte (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;
  begin
    -- Three reset edges: instruction 0 and 1 are decoded each time, but no
    -- register or RAM write may occur.
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    expect_byte("reset: r1 stays 0", regs(1), x"00");
    expect_byte("reset: RAM[3] stays 0xAA", ram(3), x"AA");
    checks := checks + 1;
    if flags /= "0000" then
      errors := errors + 1;
      report "FAIL reset: flags not cleared" severity error;
    end if;

    -- Release reset and run to HALT.
    rst <= '0';
    loop
      exit when halted = '1';
      wait until rising_edge(clk);
      cycles := cycles + 1;
      if cycles > 20 then
        report "RESET GATING: TIMEOUT" severity failure;
      end if;
      wait for 1 ns;
    end loop;

    expect_byte("after reset: r1=5", regs(1), x"05");
    expect_byte("after run: RAM[3]=5", ram(3), x"05");
    expect_byte("after run: pc=2", pc, x"02");
    checks := checks + 1;
    if cycles /= 2 then
      errors := errors + 1;
      report "FAIL after reset: expected 2 cycles, got " &
             integer'image(cycles) severity error;
    end if;

    report "reset_gating_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "RESET GATING TESTBENCH: ALL TESTS PASSED";
      done <= true;
    else
      report "RESET GATING TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 100 us;
    report "RESET GATING TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
