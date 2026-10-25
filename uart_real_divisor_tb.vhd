-- The board UART divisor is 12 MHz / 115200 = 104 clocks per bit.
-- Hand-derived busy window: ten 104-clock bits, busy high through elapsed
-- edge 1039 and low at edge 1040 after the accepted write edge.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity uart_real_divisor_tb is
end entity uart_real_divisor_tb;

architecture sim of uart_real_divisor_tb is
  constant CLK_PERIOD : time := 10 ns;
  constant CLKS_BIT   : positive := 12_000_000 / 115_200;
  constant FRAME_CYCLES : positive := 10 * CLKS_BIT;
  constant MAX_BYTES  : natural := 2;

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal addr     : byte_t := IO_UART_TX;
  signal we       : std_logic := '0';
  signal wdata    : byte_t := (others => '0');
  signal rdata    : byte_t;
  signal gpio_in  : byte_t := (others => '0');
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;
  signal rx_data  : std_logic_vector(15 downto 0);
  signal rx_count : natural range 0 to MAX_BYTES;
  signal rx_errors : natural;
begin
  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.mmio
    generic map (CLK_FREQ => 12_000_000, BAUD => 115_200)
    port map (clk => clk, rst => rst, addr => addr, we => we,
              wdata => wdata, rdata => rdata, gpio_in => gpio_in,
              gpio_out => gpio_out, uart_tx => uart_tx);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => CLKS_BIT, MAX_BYTES => MAX_BYTES)
    port map (clk => clk, rst => rst, serial => uart_tx, data => rx_data,
              count => rx_count, errors => rx_errors);

  stim : process
    variable checks : natural := 0;
    variable errors : natural := 0;
    procedure expect(name : string; condition : boolean) is
    begin
      checks := checks + 1;
      if not condition then
        errors := errors + 1;
        report "UART 104 FAIL: " & name severity error;
      end if;
    end procedure;
  begin
    assert CLKS_BIT = 104 report "derived board divisor changed" severity failure;
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';

    -- Start byte 0x55. A write one edge later is inside the busy window and
    -- must be discarded by the MMIO UART path.
    wait until falling_edge(clk);
    addr <= IO_UART_TX;
    wdata <= x"55";
    we <= '1';
    wait until rising_edge(clk);
    we <= '0';
    addr <= IO_UART_STATUS;
    wait for 1 ns;
    expect("status busy on accepted-write edge", rdata(0) = '1');

    wait until falling_edge(clk);
    addr <= IO_UART_TX;
    wdata <= x"AA";
    we <= '1';
    wait until rising_edge(clk);
    we <= '0';
    addr <= IO_UART_STATUS;

    for i in 2 to FRAME_CYCLES - 1 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      if i = FRAME_CYCLES - 1 then
        expect("busy through elapsed edge 1039", rdata(0) = '1');
      end if;
    end loop;
    wait until rising_edge(clk);
    wait for 1 ns;
    expect("idle at elapsed edge 1040", rdata(0) = '0');
    expect("busy status upper bits zero", rdata(7 downto 1) = "0000000");

    -- At the first available edge after the idle boundary, a new byte is
    -- accepted. The receiver should see exactly the first and third writes.
    wait until falling_edge(clk);
    addr <= IO_UART_TX;
    wdata <= x"A3";
    we <= '1';
    wait until rising_edge(clk);
    we <= '0';
    addr <= IO_UART_STATUS;
    wait until rx_count = 2;
    wait until rdata(0) = '0';
    wait for 1 ns;
    expect("only two bytes captured", rx_count = 2);
    expect("first byte decoded", rx_data(7 downto 0) = x"55");
    expect("second byte decoded after idle", rx_data(15 downto 8) = x"A3");
    expect("no framing errors", rx_errors = 0);

    report "uart_real_divisor_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors, divisor=" &
           integer'image(CLKS_BIT) & " busy_cycles=" &
           integer'image(FRAME_CYCLES);
    if errors = 0 then
      report "UART REAL DIVISOR TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "UART REAL DIVISOR TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 1 ms;
    report "UART REAL DIVISOR TESTBENCH: GLOBAL WATCHDOG TIMEOUT"
      severity failure;
    wait;
  end process;
end architecture sim;
