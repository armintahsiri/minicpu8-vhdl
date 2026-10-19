-- uart_tx_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Sends several bytes at a small CLK_FREQ/BAUD ratio (10 clocks/bit) and
-- captures the serial line with an independent oversampling receiver.
-- Checks start/data/stop framing, LSB-first order, the exact busy duration
-- (10 bit periods), idle-high line, and that a write while busy is ignored.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity uart_tx_tb is
end entity uart_tx_tb;

architecture sim of uart_tx_tb is
  constant CLK_PERIOD   : time    := 10 ns;
  constant CLKS_PER_BIT : natural := 10;
  constant BIT_TIME     : time    := CLK_PERIOD * CLKS_PER_BIT;
  constant MAX_BYTES    : natural := 6;

  type bytes_t is array (natural range <>) of byte_t;
  constant EXPECTED : bytes_t(0 to MAX_BYTES - 1) :=
    (x"55", x"A3", x"00", x"FF", x"48", x"69");

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal wr      : std_logic := '0';
  signal data_in : byte_t := (others => '0');
  signal tx      : std_logic;
  signal busy    : std_logic;

  signal rx_data   : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  signal rx_count  : natural range 0 to MAX_BYTES;
  signal rx_errors : natural;
begin

  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.uart_tx
    generic map (CLK_FREQ => 1_000_000, BAUD => 100_000)
    port map (clk => clk, rst => rst, wr => wr, data_in => data_in,
              tx => tx, busy => busy);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => CLKS_PER_BIT, MAX_BYTES => MAX_BYTES)
    port map (clk => clk, rst => rst, serial => tx, data => rx_data,
              count => rx_count, errors => rx_errors);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable t_write, t_fall : time;

    procedure expect (name : string; cond : boolean) is
    begin
      checks := checks + 1;
      if not cond then
        errors := errors + 1;
        report "UART FAIL: " & name severity error;
      end if;
    end procedure;
  begin
    -- Synchronous reset for two edges.
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    expect("tx idle high after reset", tx = '1');
    expect("busy low after reset", busy = '0');
    rst <= '0';

    for i in 0 to MAX_BYTES - 1 loop
      wait until falling_edge(clk);
      data_in <= EXPECTED(i);
      wr      <= '1';
      wait until rising_edge(clk);
      if i = 0 then
        t_write := now;
      end if;
      wait until falling_edge(clk);
      wr <= '0';

      if i = 0 then
        -- A second write while the first byte is in flight must be ignored.
        wait until falling_edge(clk);
        data_in <= x"AA";
        wr      <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        wr <= '0';
        expect("busy during transmission", busy = '1');
      end if;

      wait until busy = '0';
      if i = 0 then
        t_fall := now;
        expect("busy high for exactly 10 bit periods",
               t_fall - t_write = 10 * BIT_TIME);
      end if;
      wait for 1 ns;

      expect("received byte count after " & integer'image(i + 1),
             rx_count = i + 1);
      expect("framing errors after " & integer'image(i + 1),
             rx_errors = 0);
      expect("received byte " & integer'image(i),
             rx_data((i + 1) * 8 - 1 downto i * 8) = EXPECTED(i));
      expect("write-while-busy did not create an extra byte (i=" &
             integer'image(i) & ")", rx_count <= i + 1);
    end loop;

    wait for 2 * BIT_TIME;
    expect("tx idle high at end", tx = '1');
    expect("no extra bytes", rx_count = MAX_BYTES);
    expect("no framing errors at end", rx_errors = 0);

    report "uart_tx_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "UART TX TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "UART TX TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 100 us;
    report "UART TX TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

end architecture sim;
