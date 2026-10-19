-- cpu_edge_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Program-counter wrap and end-of-ROM behaviour at the CPU level:
--   1. forward BEQ wrap: branch at 0xFE with +2 lands at 0x01 (0xFF + 2 mod 256)
--   2. backward BEQ wrap: branch at 0x00 with -2 lands at 0xFF (1 - 2 mod 256)
--   3. JMP to 0xFF executes the HALT at the last ROM word
--   4. falling off the end of a one-word program into the HALT-filled ROM
-- Mod-256 PC wrap is intended behaviour (documented in docs/ISA.md).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity cpu_edge_tb is
end entity cpu_edge_tb;

architecture sim of cpu_edge_tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal halted_f, halted_b, halted_j, halted_e : std_logic;
  signal pc_f, pc_b, pc_j, pc_e : byte_t;
  signal fl_f, fl_b, fl_j, fl_e : std_logic_vector(3 downto 0);
  signal rf_f, rf_b, rf_j, rf_e : regfile_t;
  signal ram_f, ram_b, ram_j, ram_e : ram_t;
  constant EMPTY_RAM : ram_init_t(0 to 0) := (0 => x"00");

  -- forward wrap: jmp 0xFD; at 0xFD loadi r1,1; at 0xFE beq r0,r0,+2 -> 0x01
  constant PROG_FWD : rom_t(0 to 255) := (
    0      => x"C0FD",   -- jmp 0xFD
    1      => x"941F",   -- loadi r2, 31   (landing point after the wrap)
    2      => x"F001",   -- halt
    16#FD# => x"9201",   -- loadi r1, 1
    16#FE# => x"A002",   -- beq r0,r0,+2  -> (0xFE+1+2) mod 256 = 0x01
    16#FF# => x"F001",   -- halt (skipped)
    others => x"F001");

  -- backward wrap: at 0x00 beq r0,r0,-2 -> 0xFF; at 0xFF jmp 0x02
  constant PROG_BWD : rom_t(0 to 255) := (
    0      => x"A03E",   -- beq r0,r0,-2  -> (0+1-2) mod 256 = 0xFF
    1      => x"F001",
    2      => x"9607",   -- loadi r3, 7
    3      => x"F001",   -- halt
    16#FF# => x"C002",   -- jmp 0x02
    others => x"F001");

  -- jump to the last ROM word, which is HALT
  constant PROG_JMPFF : rom_t(0 to 255) := (
    0      => x"C0FF",   -- jmp 0xFF
    16#FF# => x"F001",   -- halt
    others => x"F001");

  -- one-word program: execution runs off the end into the ROM's HALT filler
  constant PROG_END : rom_t(0 to 0) := (
    0 => x"9205");       -- loadi r1, 5

  constant MAX_CYCLES : natural := 50;
  signal done : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut_f : entity work.cpu_top
    generic map (PROGRAM => PROG_FWD, RAM_INIT => EMPTY_RAM)
    port map (clk => clk, rst => rst, halted => halted_f,
              dbg_pc => pc_f, dbg_flags => fl_f, dbg_regs => rf_f,
              dbg_ram => ram_f);

  dut_b : entity work.cpu_top
    generic map (PROGRAM => PROG_BWD, RAM_INIT => EMPTY_RAM)
    port map (clk => clk, rst => rst, halted => halted_b,
              dbg_pc => pc_b, dbg_flags => fl_b, dbg_regs => rf_b,
              dbg_ram => ram_b);

  dut_j : entity work.cpu_top
    generic map (PROGRAM => PROG_JMPFF, RAM_INIT => EMPTY_RAM)
    port map (clk => clk, rst => rst, halted => halted_j,
              dbg_pc => pc_j, dbg_flags => fl_j, dbg_regs => rf_j,
              dbg_ram => ram_j);

  dut_e : entity work.cpu_top
    generic map (PROGRAM => PROG_END, RAM_INIT => EMPTY_RAM)
    port map (clk => clk, rst => rst, halted => halted_e,
              dbg_pc => pc_e, dbg_flags => fl_e, dbg_regs => rf_e,
              dbg_ram => ram_e);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : natural := 0;

    procedure expect_byte (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "EDGE FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;

    procedure expect_halted (name : string; h : std_logic) is
    begin
      checks := checks + 1;
      if h /= '1' then
        errors := errors + 1;
        report "EDGE FAIL " & name & " did not halt" severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    while (halted_f /= '1' or halted_b /= '1' or
           halted_j /= '1' or halted_e /= '1') loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when cycles > MAX_CYCLES;
    end loop;
    wait for 1 ns;

    if cycles > MAX_CYCLES then
      report "EDGE TEST: TIMEOUT after " & integer'image(MAX_CYCLES) &
             " cycles" severity failure;
    end if;

    -- forward wrap landed at 0x01 and ran the marker instruction
    expect_halted("forward wrap", halted_f);
    expect_byte("forward wrap r1", rf_f(1), x"01");
    expect_byte("forward wrap r2", rf_f(2), x"1F");
    expect_byte("forward wrap pc", pc_f, x"02");

    -- backward wrap landed at 0xFF, jumped to 0x02 and halted there
    expect_halted("backward wrap", halted_b);
    expect_byte("backward wrap r3", rf_b(3), x"07");
    expect_byte("backward wrap pc", pc_b, x"03");

    -- jmp 0xFF executed the HALT in the last ROM word
    expect_halted("jmp 0xFF", halted_j);
    expect_byte("jmp 0xFF pc", pc_j, x"FF");

    -- running off the end fell into the HALT fill at address 1
    expect_halted("fall off end", halted_e);
    expect_byte("fall off end r1", rf_e(1), x"05");
    expect_byte("fall off end pc", pc_e, x"01");

    report "cpu_edge_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors (halted after " &
           integer'image(cycles) & " cycles)";
    if errors = 0 then
      report "CPU EDGE TESTBENCH: ALL TESTS PASSED";
      done <= true;
    else
      report "CPU EDGE TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 100 us;
    report "CPU EDGE TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
