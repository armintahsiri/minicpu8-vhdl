-- data_ram_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Init contents (sparse pattern + zero fill), read/write, write-enable
-- gating, read-during-write (old value before the edge), and the 0x00/0xFF
-- address endpoints.  Address wrap itself is tested at CPU level.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity data_ram_tb is
end entity data_ram_tb;

architecture sim of data_ram_tb is
  signal clk   : std_logic := '0';
  signal we    : std_logic := '0';
  signal addr  : byte_t := (others => '0');
  signal wdata : byte_t := (others => '0');
  signal rdata : byte_t;
  signal dbg   : ram_t;

  constant INIT : ram_init_t(0 to 4) :=
    (0 => x"11", 1 => x"22", 2 => x"33", 3 => x"44", 4 => x"55");
begin

  clk <= not clk after 5 ns;

  dut : entity work.data_ram
    generic map (INIT => INIT)
    port map (clk => clk, we => we, addr => addr, wdata => wdata,
              rdata => rdata, dbg => dbg);

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

    procedure read_at (a : natural; exp : byte_t; name : string) is
    begin
      addr <= std_logic_vector(to_unsigned(a, 8));
      wait for 1 ns;
      expect(name, rdata, exp);
    end procedure;

    procedure write_at (a : natural; d : byte_t) is
    begin
      wait until falling_edge(clk);
      addr <= std_logic_vector(to_unsigned(a, 8));
      wdata <= d;
      we <= '1';
      wait until falling_edge(clk);   -- rising edge performs the write
      we <= '0';
    end procedure;
  begin
    -- init contents
    read_at(0, x"11", "init 0");
    read_at(1, x"22", "init 1");
    read_at(2, x"33", "init 2");
    read_at(4, x"55", "init 4");
    read_at(5, x"00", "zero fill above init");
    read_at(200, x"00", "zero fill high address");
    read_at(255, x"00", "zero fill last address");

    -- write and read back
    write_at(10, x"A5");
    read_at(10, x"A5", "write/read 10");
    write_at(10, x"5A");
    read_at(10, x"5A", "overwrite 10");

    -- write-enable gating
    wait until falling_edge(clk);
    addr <= std_logic_vector(to_unsigned(11, 8));
    wdata <= x"99";
    we <= '0';
    wait until falling_edge(clk);     -- edge with we=0
    we <= '0';
    read_at(11, x"00", "we=0 does not write");

    -- read-during-write: old value before the edge, new value after
    wait until falling_edge(clk);
    addr <= std_logic_vector(to_unsigned(12, 8));
    wdata <= x"77";
    we <= '1';
    wait for 1 ns;
    expect("read before write edge (old)", rdata, x"00");
    wait until falling_edge(clk);
    we <= '0';
    expect("read after write edge (new)", rdata, x"77");

    -- endpoints 0x00 and 0xFF are both writable/readable
    write_at(0, x"AA");
    read_at(0, x"AA", "address 0x00");
    write_at(255, x"BB");
    read_at(255, x"BB", "address 0xFF");
    expect("dbg(255)", dbg(255), x"BB");
    expect("dbg(10)", dbg(10), x"5A");

    report "data_ram_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "DATA RAM TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "DATA RAM TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
