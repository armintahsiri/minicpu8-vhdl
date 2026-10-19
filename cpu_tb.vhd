-- cpu_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- System-level tests: two cpu_top instances, each running one program.
--   DUT 1: sum1to10      -> r1 must equal 55 (0x37) after HALT
--   DUT 2: shift_branch  -> r2=12 r3=6 r4=10 r5=13 r6=0, flags ZNCV=0000
-- A per-DUT cycle budget stops broken programs from hanging the simulation,
-- plus a global wall-clock watchdog.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity cpu_tb is
end entity cpu_tb;

architecture sim of cpu_tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal halted1 : std_logic;
  signal pc1     : byte_t;
  signal fl1     : std_logic_vector(3 downto 0);
  signal regs1   : regfile_t;

  signal halted2 : std_logic;
  signal pc2     : byte_t;
  signal fl2     : std_logic_vector(3 downto 0);
  signal regs2   : regfile_t;

  signal done1, done2 : boolean := false;

  constant MAX_CYCLES : natural := 2000;
begin

  clk <= not clk after 5 ns;

  dut1 : entity work.cpu_top
    generic map (PROGRAM => work.sum1to10_rom.PROG)
    port map (clk => clk, rst => rst, halted => halted1,
              dbg_pc => pc1, dbg_flags => fl1, dbg_regs => regs1);

  dut2 : entity work.cpu_top
    generic map (PROGRAM => work.shift_branch_rom.PROG)
    port map (clk => clk, rst => rst, halted => halted2,
              dbg_pc => pc2, dbg_flags => fl2, dbg_regs => regs2);

  sum_check : process
    variable errors  : natural := 0;
    variable checks  : natural := 0;
    variable cycles  : natural := 0;

    procedure expect (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "SUM FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);              -- instruction 0 executes on this edge

    while halted1 /= '1' loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when cycles > MAX_CYCLES;
    end loop;
    wait for 1 ns;

    if cycles > MAX_CYCLES then
      report "SUM TEST: TIMEOUT after " & integer'image(MAX_CYCLES) &
             " cycles (CPU did not halt)" severity failure;
    end if;

    -- sum of 1..10 = 55 = 0x37
    expect("r1 = 55",       regs1(1), std_logic_vector(to_unsigned(55, 8)));
    expect("halt address",  pc1, std_logic_vector(to_unsigned(7, 8)));
    expect("i ended at 11", regs1(2), std_logic_vector(to_unsigned(11, 8)));
    checks := checks + 1;
    if halted1 /= '1' then
      errors := errors + 1;
      report "SUM FAIL halted is not '1'" severity error;
    end if;

    report "cpu_tb sum1to10: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors (halted after " &
           integer'image(cycles) & " cycles)";
    if errors = 0 then
      report "SUM 1..10 TEST PASSED: r1 = 55";
    else
      report "SUM 1..10 TEST FAILED" severity failure;
    end if;
    done1 <= true;
    wait;
  end process;

  shift_check : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : natural := 0;

    procedure expect (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "SHIFT FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    while halted2 /= '1' loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when cycles > MAX_CYCLES;
    end loop;
    wait for 1 ns;

    if cycles > MAX_CYCLES then
      report "SHIFT TEST: TIMEOUT after " & integer'image(MAX_CYCLES) &
             " cycles (CPU did not halt)" severity failure;
    end if;

    expect("r1 = 3",          regs2(1), std_logic_vector(to_unsigned(3, 8)));
    expect("r2 = 3 shl 2",    regs2(2), std_logic_vector(to_unsigned(12, 8)));
    expect("r3 = 12 shr 1",   regs2(3), std_logic_vector(to_unsigned(6, 8)));
    expect("r4 = 12 xor 6",   regs2(4), std_logic_vector(to_unsigned(10, 8)));
    expect("r5 = 10 add 3",   regs2(5), std_logic_vector(to_unsigned(13, 8)));
    expect("r6 = 0 (beq taken, loadi skipped)",
           regs2(6), x"00");
    expect("halt address",    pc2, std_logic_vector(to_unsigned(9, 8)));
    -- last flag-writing op was add r5,r4,r1 = 13 -> Z=0 N=0 C=0 V=0
    checks := checks + 1;
    if fl2 /= "0000" then
      errors := errors + 1;
      report "SHIFT FAIL flags ZNCV got=" & to_string(fl2) &
             " expected=0000" severity error;
    end if;

    report "cpu_tb shift_branch: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors (halted after " &
           integer'image(cycles) & " cycles)";
    if errors = 0 then
      report "SHIFT/BRANCH TEST PASSED";
    else
      report "SHIFT/BRANCH TEST FAILED" severity failure;
    end if;
    done2 <= true;
    wait;
  end process;

  -- global watchdog: nothing may take longer than this wall-clock time
  watchdog : process
  begin
    wait for 100 us;
    report "GLOBAL WATCHDOG: simulation timed out" severity failure;
    wait;
  end process;

  finisher : process
  begin
    wait until done1 and done2;
    report "CPU TESTBENCH: ALL TESTS PASSED";
    finish;
  end process;

end architecture sim;
