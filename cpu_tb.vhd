-- cpu_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- System-level tests: one cpu_top instance per program, all running
-- concurrently.  Final registers, flags, PC and data RAM are asserted against
-- values pre-computed with tools/isa_sim.py.
--
-- Programs (index):
--   0 sum1to10          1 shift_branch       2 array_sum
--   3 find_max          4 call_ret           5 unsigned_vs_signed
--   6 pc_wrap           7 r0_guard
--
-- Each program has its own cycle budget; a global wall-clock watchdog stops a
-- broken simulation.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity cpu_tb is
end entity cpu_tb;

architecture sim of cpu_tb is
  type halted_vec_t  is array (natural range <>) of std_logic;
  type pc_vec_t      is array (natural range <>) of byte_t;
  type flags_vec_t   is array (natural range <>) of std_logic_vector(3 downto 0);
  type regs_vec_t    is array (natural range <>) of regfile_t;
  type ram_vec_t     is array (natural range <>) of ram_t;
  type cycle_vec_t   is array (natural range <>) of natural;
  type bool_vec_t    is array (natural range <>) of boolean;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal halted_v : halted_vec_t(0 to 7);
  signal pc_v     : pc_vec_t(0 to 7);
  signal flags_v  : flags_vec_t(0 to 7);
  signal regs_v   : regs_vec_t(0 to 7);
  signal ram_v    : ram_vec_t(0 to 7);

  constant CYCLE_BUDGET : cycle_vec_t(0 to 7) :=
    (100, 50, 200, 150, 600, 50, 20, 50);
  constant EXPECTED_CYCLES : cycle_vec_t(0 to 7) :=
    (33, 8, 54, 32, 179, 10, 4, 7);
  constant MAX_CYCLES : natural := 600;

  signal done : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut0 : entity work.cpu_top
    generic map (PROGRAM => work.sum1to10_rom.PROG,
                 RAM_INIT => work.sum1to10_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(0),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(0), dbg_flags => flags_v(0),
              dbg_regs => regs_v(0), dbg_ram => ram_v(0));

  dut1 : entity work.cpu_top
    generic map (PROGRAM => work.shift_branch_rom.PROG,
                 RAM_INIT => work.shift_branch_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(1),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(1), dbg_flags => flags_v(1),
              dbg_regs => regs_v(1), dbg_ram => ram_v(1));

  dut2 : entity work.cpu_top
    generic map (PROGRAM => work.array_sum_rom.PROG,
                 RAM_INIT => work.array_sum_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(2),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(2), dbg_flags => flags_v(2),
              dbg_regs => regs_v(2), dbg_ram => ram_v(2));

  dut3 : entity work.cpu_top
    generic map (PROGRAM => work.find_max_rom.PROG,
                 RAM_INIT => work.find_max_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(3),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(3), dbg_flags => flags_v(3),
              dbg_regs => regs_v(3), dbg_ram => ram_v(3));

  dut4 : entity work.cpu_top
    generic map (PROGRAM => work.call_ret_rom.PROG,
                 RAM_INIT => work.call_ret_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(4),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(4), dbg_flags => flags_v(4),
              dbg_regs => regs_v(4), dbg_ram => ram_v(4));

  dut5 : entity work.cpu_top
    generic map (PROGRAM => work.unsigned_vs_signed_rom.PROG,
                 RAM_INIT => work.unsigned_vs_signed_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(5),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(5), dbg_flags => flags_v(5),
              dbg_regs => regs_v(5), dbg_ram => ram_v(5));

  dut6 : entity work.cpu_top
    generic map (PROGRAM => work.pc_wrap_rom.PROG,
                 RAM_INIT => work.pc_wrap_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(6),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(6), dbg_flags => flags_v(6),
              dbg_regs => regs_v(6), dbg_ram => ram_v(6));

  dut7 : entity work.cpu_top
    generic map (PROGRAM => work.r0_guard_rom.PROG,
                 RAM_INIT => work.r0_guard_ram.INIT)
    port map (clk => clk, rst => rst, halted => halted_v(7),
              gpio_in => x"00", gpio_out => open, uart_tx => open,
              dbg_pc => pc_v(7), dbg_flags => flags_v(7),
              dbg_regs => regs_v(7), dbg_ram => ram_v(7));

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : cycle_vec_t(0 to 7) := (others => 0);
    variable active : bool_vec_t(0 to 7) := (others => true);
    variable all_halted : boolean;

    procedure expect_byte (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;

    procedure expect_flags (name : string; got : std_logic_vector(3 downto 0);
                            exp : std_logic_vector(3 downto 0)) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " flags got=" & to_string(got) &
               " expected=" & to_string(exp) severity error;
      end if;
    end procedure;

    procedure expect_cycles (name : string; got, exp : natural) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " cycles got=" & integer'image(got) &
               " expected=" & integer'image(exp) severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    -- While reset is asserted no architectural write may happen.  r0_guard's
    -- first instruction is loadi r1,16; array_sum's first is loadi r2,16.
    expect_byte("reset suppresses r0_guard r1", regs_v(7)(1), x"00");
    expect_byte("reset suppresses array_sum r2", regs_v(2)(2), x"00");
    rst <= '0';

    -- Count one cycle for every rising edge on which a program is still
    -- running.  HALT is detected before it is "executed", matching isa_sim.
    loop
      all_halted := true;
      for i in 0 to 7 loop
        active(i) := halted_v(i) /= '1';
        if active(i) then
          all_halted := false;
        end if;
      end loop;
      exit when all_halted;

      wait until rising_edge(clk);
      for i in 0 to 7 loop
        if active(i) then
          cycles(i) := cycles(i) + 1;
          if cycles(i) > CYCLE_BUDGET(i) then
            report "PROGRAM " & integer'image(i) & " CYCLE BUDGET EXCEEDED"
              severity failure;
          end if;
        end if;
      end loop;
      -- Let the combinational PC/ROM/control chain settle before testing
      -- halted at the top of the loop; otherwise HALT can be observed one
      -- delta too late and an extra (non-executed) cycle gets counted.
      wait for 1 ns;
    end loop;
    wait for 1 ns;

    for i in 0 to 7 loop
      checks := checks + 1;
      if halted_v(i) /= '1' then
        errors := errors + 1;
        report "FAIL program " & integer'image(i) & " did not halt"
          severity error;
      end if;
      expect_cycles("program " & integer'image(i), cycles(i), EXPECTED_CYCLES(i));
    end loop;

    -- 0: sum1to10
    expect_byte("sum r1=55", regs_v(0)(1), x"37");
    expect_byte("sum i=11", regs_v(0)(2), x"0B");
    expect_byte("sum pc=6", pc_v(0), x"06");
    expect_flags("sum flags", flags_v(0), "0000");

    -- 1: shift_branch
    expect_byte("shift r1=3", regs_v(1)(1), x"03");
    expect_byte("shift r2=12", regs_v(1)(2), x"0C");
    expect_byte("shift r3=6", regs_v(1)(3), x"06");
    expect_byte("shift r4=10", regs_v(1)(4), x"0A");
    expect_byte("shift r5=13", regs_v(1)(5), x"0D");
    expect_byte("shift r6=0", regs_v(1)(6), x"00");
    expect_byte("shift pc=9", pc_v(1), x"09");
    expect_flags("shift flags", flags_v(1), "0000");

    -- 2: array_sum
    expect_byte("array_sum r1=55", regs_v(2)(1), x"37");
    expect_byte("array_sum pointer=26", regs_v(2)(2), x"1A");
    expect_byte("array_sum count=0", regs_v(2)(3), x"00");
    expect_byte("array_sum last=10", regs_v(2)(5), x"0A");
    expect_byte("array_sum RAM[26]=55", ram_v(2)(26), x"37");
    expect_byte("array_sum RAM[16]=1", ram_v(2)(16), x"01");
    expect_byte("array_sum pc=9", pc_v(2), x"09");
    expect_flags("array_sum flags", flags_v(2), "1010");

    -- 3: find_max (signed)
    expect_byte("find_max max=127", regs_v(3)(1), x"7F");
    expect_byte("find_max pointer=21", regs_v(3)(2), x"15");
    expect_byte("find_max last=127", regs_v(3)(5), x"7F");
    expect_byte("find_max RAM[21]=127", ram_v(3)(21), x"7F");
    expect_byte("find_max RAM[16]=-5", ram_v(3)(16), x"FB");
    expect_byte("find_max RAM[19]=-100", ram_v(3)(19), x"9C");
    expect_byte("find_max pc=13", pc_v(3), x"0D");
    expect_flags("find_max flags", flags_v(3), "1010");

    -- 4: call_ret (two calls + nested call with R7 saved in RAM[20])
    expect_byte("call_ret 3*5=15", ram_v(4)(16), x"0F");
    expect_byte("call_ret 7*6=42", ram_v(4)(17), x"2A");
    expect_byte("call_ret 9*9=81", ram_v(4)(18), x"51");
    expect_byte("call_ret saved link=10", ram_v(4)(20), x"0A");
    expect_byte("call_ret r7=10", regs_v(4)(7), x"0A");
    expect_byte("call_ret r3=81", regs_v(4)(3), x"51");
    expect_byte("call_ret pc=11", pc_v(4), x"0B");
    expect_flags("call_ret flags", flags_v(4), "0000");

    -- 5: unsigned_vs_signed
    expect_byte("unsigned r3=2 (BHS)", regs_v(5)(3), x"02");
    expect_byte("signed r4=3 (BLT)", regs_v(5)(4), x"03");
    expect_byte("unsigned r1=0xFE", regs_v(5)(1), x"FE");
    expect_byte("unsigned pc=18", pc_v(5), x"12");
    expect_flags("unsigned_vs_signed flags", flags_v(5), "0110");

    -- 6: pc_wrap
    expect_byte("pc_wrap r1=1", regs_v(6)(1), x"01");
    expect_byte("pc_wrap r2=31", regs_v(6)(2), x"1F");
    expect_byte("pc_wrap pc=2", pc_v(6), x"02");
    expect_flags("pc_wrap flags", flags_v(6), "0000");

    -- 7: r0_guard
    expect_byte("r0_guard r0=0", regs_v(7)(0), x"00");
    expect_byte("r0_guard r1=16", regs_v(7)(1), x"10");
    expect_byte("r0_guard r7=5", regs_v(7)(7), x"05");
    expect_byte("r0_guard RAM[3]=0", ram_v(7)(3), x"00");
    expect_byte("r0_guard RAM[16]=0x5A", ram_v(7)(16), x"5A");
    expect_byte("r0_guard pc=5", pc_v(7), x"05");
    expect_flags("r0_guard flags", flags_v(7), "0000");

    report "cpu_tb:" & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors" &
           " cycles: sum=" & integer'image(cycles(0)) &
           " shift=" & integer'image(cycles(1)) &
           " array_sum=" & integer'image(cycles(2)) &
           " find_max=" & integer'image(cycles(3)) &
           " call_ret=" & integer'image(cycles(4)) &
           " unsigned=" & integer'image(cycles(5)) &
           " pc_wrap=" & integer'image(cycles(6)) &
           " r0_guard=" & integer'image(cycles(7));
    if errors = 0 then
      report "CPU PROGRAMS TESTBENCH: ALL TESTS PASSED";
      done <= true;
    else
      report "CPU PROGRAMS TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 200 us;
    report "CPU TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
