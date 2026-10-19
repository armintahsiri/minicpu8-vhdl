-- register_file_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Self-checking tests: write/read via both ports, R0 hardwired zero,
-- write-ignore on R0, read-during-write returns old value.
-- All stimulus is applied just after a falling clock edge so it is stable
-- at the following rising (write) edge; results are checked after edges.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity register_file_tb is
end entity register_file_tb;

architecture sim of register_file_tb is
  signal clk    : std_logic := '0';
  signal raddr1 : regsel_t := (others => '0');
  signal raddr2 : regsel_t := (others => '0');
  signal waddr  : regsel_t := (others => '0');
  signal wdata  : byte_t   := (others => '0');
  signal we     : std_logic := '0';
  signal rd1, rd2 : byte_t;
  signal dbg     : regfile_t;
begin

  clk <= not clk after 5 ns;

  dut : entity work.register_file
    port map (clk => clk, raddr1 => raddr1, raddr2 => raddr2,
              waddr => waddr, wdata => wdata, we => we,
              rd1 => rd1, rd2 => rd2, dbg => dbg);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    procedure expect (name : string; got, exp : byte_t) is
    begin
      checks := checks + 1;
      if got /= exp then
        errors := errors + 1;
        report "FAIL " & name & " got=0x" & to_hstring(got) &
               " expected=0x" & to_hstring(exp) severity error;
      end if;
    end procedure;

    -- set read addresses (combinational), settle
    procedure rd (p1, p2 : natural) is
    begin
      raddr1 <= std_logic_vector(to_unsigned(p1, 3));
      raddr2 <= std_logic_vector(to_unsigned(p2, 3));
      wait for 1 ns;
    end procedure;

    -- write one register: anchored at falling edges, one rising edge in between
    procedure wr (a : natural; d : byte_t) is
    begin
      wait until falling_edge(clk);
      waddr <= std_logic_vector(to_unsigned(a, 3));
      wdata <= d;
      we    <= '1';
      wait until falling_edge(clk);   -- rising edge in between applied the write
      we    <= '0';
    end procedure;
  begin
    -- R0 reads zero on both ports before anything is written
    rd(0, 0);
    expect("R0 port1 initial", rd1, x"00");
    expect("R0 port2 initial", rd2, x"00");

    -- write R1..R7, read back through both ports
    for i in 1 to 7 loop
      wr(i, std_logic_vector(to_unsigned(i * 16 + i, 8)));  -- 0x11..0x77
    end loop;
    rd(1, 2); expect("R1 via port1", rd1, x"11"); expect("R2 via port2", rd2, x"22");
    rd(3, 4); expect("R3 via port1", rd1, x"33"); expect("R4 via port2", rd2, x"44");
    rd(5, 6); expect("R5 via port1", rd1, x"55"); expect("R6 via port2", rd2, x"66");
    rd(7, 0); expect("R7 via port1", rd1, x"77"); expect("R0 port2", rd2, x"00");

    -- same register on both ports at once
    rd(3, 3); expect("R3 dual port1", rd1, x"33"); expect("R3 dual port2", rd2, x"33");

    -- attempt to write R0: must stay zero
    wr(0, x"FF");
    rd(0, 0);
    expect("R0 after write attempt", rd1, x"00");
    expect("dbg(0) stays zero", dbg(0), x"00");

    -- overwrite R1 with a new value
    wr(1, x"A5");
    rd(1, 1);
    expect("R1 overwritten", rd1, x"A5");

    -- read-during-write: async read shows old value before the edge,
    -- new value after the edge
    wait until falling_edge(clk);
    raddr1 <= "010";                 -- watch R2 on port 1
    waddr  <= "010";                 -- write R2 in the same cycle
    wdata  <= x"5C";
    we     <= '1';
    wait for 1 ns;                   -- still before the rising edge
    expect("R2 before edge (old)", rd1, x"22");
    wait until falling_edge(clk);    -- rising edge passed: write applied
    we <= '0';
    expect("R2 after edge (new)", rd1, x"5C");

    -- we=0: no write happens
    wait until falling_edge(clk);
    waddr <= "011"; wdata <= x"99"; we <= '0';
    wait until falling_edge(clk);    -- rising edge passed with we=0
    rd(3, 3);
    expect("R3 unchanged when we=0", rd1, x"33");

    -- dbg view matches
    expect("dbg(1)", dbg(1), x"A5");
    expect("dbg(2)", dbg(2), x"5C");

    report "register_file_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "REGISTER FILE TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "REGISTER FILE TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
