-- mmio_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Unit-level tests of the MMIO block: address decode/read values, GPIO
-- write/readback and input synchronizer, cycle counter reads, UART status,
-- UART write-while-busy ignored, and independent UART byte capture.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity mmio_tb is
end entity mmio_tb;

architecture sim of mmio_tb is
  constant CLK_PERIOD   : time    := 10 ns;
  constant CLKS_PER_BIT : natural := 10;
  constant MAX_BYTES    : natural := 4;

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal addr     : byte_t := (others => '0');
  signal we       : std_logic := '0';
  signal wdata    : byte_t := (others => '0');
  signal rdata    : byte_t;
  signal gpio_in  : byte_t := (others => '0');
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;

  signal rx_data   : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  signal rx_count  : natural range 0 to MAX_BYTES;
  signal rx_errors : natural;
begin

  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.mmio
    generic map (CLK_FREQ => 1_000_000, BAUD => 100_000)
    port map (clk => clk, rst => rst, addr => addr, we => we,
              wdata => wdata, rdata => rdata, gpio_in => gpio_in,
              gpio_out => gpio_out, uart_tx => uart_tx);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => CLKS_PER_BIT, MAX_BYTES => MAX_BYTES)
    port map (clk => clk, rst => rst, serial => uart_tx, data => rx_data,
              count => rx_count, errors => rx_errors);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable c0, c1 : natural;

    procedure expect (name : string; cond : boolean) is
    begin
      checks := checks + 1;
      if not cond then
        errors := errors + 1;
        report "MMIO FAIL: " & name severity error;
      end if;
    end procedure;

    procedure read_addr (a : byte_t; exp : natural; name : string) is
    begin
      addr <= a;
      we   <= '0';
      wait for 1 ns;
      expect(name & " value",
             to_integer(unsigned(rdata)) = exp);
    end procedure;

    procedure write_addr (a : byte_t; d : byte_t) is
    begin
      wait until falling_edge(clk);
      addr  <= a;
      wdata <= d;
      we    <= '1';
      wait until rising_edge(clk);
      wait until falling_edge(clk);
      we <= '0';
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    expect("reset gpio_out pin", gpio_out = x"00");
    rst <= '0';
    wait for 1 ns;

    -- Reset/default readable values.
    read_addr(IO_UART_TX, 0, "UART_TX write-only reads 0");
    read_addr(IO_UART_STATUS, 0, "UART_STATUS idle");
    read_addr(IO_GPIO_OUT, 0, "GPIO_OUT reset");
    read_addr(IO_GPIO_IN, 0, "GPIO_IN reset sync");
    read_addr(IO_RESERVED_LO, 0, "reserved 0xF5");
    read_addr(IO_RESERVED_HI, 0, "reserved 0xFF");

    -- GPIO output and readback.
    write_addr(IO_GPIO_OUT, x"5A");
    wait for 1 ns;
    expect("GPIO_OUT pin", gpio_out = x"5A");
    read_addr(IO_GPIO_OUT, 16#5A#, "GPIO_OUT readback");

    -- GPIO input needs two edges to cross the synchronizer.
    gpio_in <= x"C3";
    wait until rising_edge(clk);
    wait for 1 ns;
    read_addr(IO_GPIO_IN, 16#00#, "GPIO_IN after one edge");
    wait until rising_edge(clk);
    wait for 1 ns;
    read_addr(IO_GPIO_IN, 16#C3#, "GPIO_IN after two edges");

    -- Cycle counter advances by one per clock.
    addr <= IO_CYCLE_LO;
    wait for 1 ns;
    c0 := to_integer(unsigned(rdata));
    for i in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    c1 := to_integer(unsigned(rdata));
    expect("cycle counter +4", c1 = ((c0 + 4) mod 256));

    -- UART: accepted byte sets busy immediately; a busy write is ignored.
    write_addr(IO_UART_TX, x"41");
    wait for 1 ns;
    read_addr(IO_UART_STATUS, 1, "UART_STATUS busy");
    expect("status unused bits zero", rdata(7 downto 1) = "0000000");
    read_addr(IO_UART_TX, 0, "UART_TX reads 0 while busy");
    write_addr(IO_UART_TX, x"42");         -- must be ignored
    read_addr(IO_UART_STATUS, 1, "status still busy after ignored write");

    -- Poll status until idle.
    addr <= IO_UART_STATUS;
    we   <= '0';
    for i in 1 to 200 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      exit when rdata(0) = '0';
    end loop;
    expect("UART became idle", rdata(0) = '0');
    wait for 1 ns;
    expect("one byte captured", rx_count = 1);
    expect("captured byte is 0x41",
           rx_data(7 downto 0) = x"41");
    expect("no UART framing errors", rx_errors = 0);

    -- Next write is accepted after busy clears.
    write_addr(IO_UART_TX, x"42");
    addr <= IO_UART_STATUS;
    we   <= '0';
    for i in 1 to 200 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      exit when rdata(0) = '0';
    end loop;
    expect("UART idle again", rdata(0) = '0');
    wait for 1 ns;
    expect("two bytes captured", rx_count = 2);
    expect("second captured byte is 0x42",
           rx_data(15 downto 8) = x"42");

    -- Writes to read-only/reserved addresses must have no effect.
    write_addr(IO_UART_STATUS, x"FF");
    write_addr(IO_GPIO_IN, x"FF");
    write_addr(IO_CYCLE_LO, x"FF");
    write_addr(IO_RESERVED_LO, x"FF");
    read_addr(IO_GPIO_OUT, 16#5A#, "GPIO_OUT unchanged by RO writes");
    read_addr(IO_RESERVED_LO, 0, "reserved still reads 0");

    report "mmio_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "MMIO TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "MMIO TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 100 us;
    report "MMIO TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

end architecture sim;
