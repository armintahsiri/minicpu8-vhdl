-- mmio.vhd : memory-mapped I/O for MiniCPU-8
-- Addresses 0xF0..0xFF (see docs/ISA.md section 8). The CPU address decoder
-- selects this block only for LOAD/STORE addresses >= IO_BASE; normal RAM is
-- untouched. Reads are combinational (single-cycle LOAD), writes are
-- synchronous. Writes to read-only/reserved addresses are ignored; reads from
-- UART_TX (write-only) and reserved addresses return 0x00.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity mmio is
  generic (
    CLK_FREQ : positive := 25_000_000;
    BAUD     : positive := 115_200);
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    addr     : in  byte_t;                -- already known to be >= IO_BASE
    we       : in  std_logic;             -- STORE in the I/O region, reset-gated
    wdata    : in  byte_t;
    rdata    : out byte_t;                -- combinational read
    gpio_in  : in  byte_t;
    gpio_out : out byte_t;
    uart_tx  : out std_logic);
end entity mmio;

architecture rtl of mmio is
  signal uart_busy    : std_logic;
  signal uart_wr      : std_logic;
  signal gpio_we      : std_logic;
  signal gpio_rd      : byte_t;
  signal gpio_in_sync : byte_t;
  signal cycle_lo     : byte_t;
begin

  -- Writes while the transmitter is busy are ignored. This is the documented
  -- policy: there is no queue and no overwrite of an in-flight byte.
  uart_wr <= '1' when we = '1' and addr = IO_UART_TX and uart_busy = '0'
             else '0';
  busy_write_guard : process (clk) is
  begin
    if rising_edge(clk) then
      assert not (we = '1' and addr = IO_UART_TX and uart_busy = '1' and
                  uart_wr = '1')
        report "MMIO asserted uart_wr while transmitter busy" severity failure;
    end if;
  end process;
  gpio_we <= '1' when we = '1' and addr = IO_GPIO_OUT else '0';

  uart_i : entity work.uart_tx
    generic map (CLK_FREQ => CLK_FREQ, BAUD => BAUD)
    port map (clk => clk, rst => rst, wr => uart_wr, data_in => wdata,
              tx => uart_tx, busy => uart_busy);

  gpio_i : entity work.gpio
    port map (clk => clk, rst => rst, we => gpio_we, wdata => wdata,
              rd_out => gpio_rd, pin_in => gpio_in,
              pin_out => gpio_out, in_sync => gpio_in_sync);

  cycles_i : entity work.cycle_counter
    port map (clk => clk, rst => rst, count => cycle_lo);

  read_p : process (all) is
  begin
    rdata <= x"00";                       -- write-only / reserved reads
    case addr is
      when IO_UART_STATUS =>
        rdata    <= (others => '0');
        rdata(0) <= uart_busy;            -- bit0 = tx_busy, bits7:1 = 0
      when IO_GPIO_OUT =>
        rdata <= gpio_rd;
      when IO_GPIO_IN =>
        rdata <= gpio_in_sync;
      when IO_CYCLE_LO =>
        rdata <= cycle_lo;
      when others =>
        null;                             -- UART_TX and 0xF5..0xFF read 0
    end case;
  end process;

end architecture rtl;
