-- uart_tx.vhd : 8N1 UART transmitter for MiniCPU-8
-- Idle line is high. A one-cycle 'wr' pulse while idle loads data_in and
-- starts: 1 start bit (0), 8 data bits LSB first, 1 stop bit (1). The busy
-- output is high from the write edge until the end of the stop bit, i.e. for
-- exactly 10 bit periods. Writes while busy are ignored (no queue).
--
-- The baud divisor is CLK_FREQ / BAUD, truncated to an integer. This is a
-- simple, documented approximation; the actual baud rate is
-- CLK_FREQ / CLKS_PER_BIT. CLKS_PER_BIT must be at least 2.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity uart_tx is
  generic (
    CLK_FREQ : positive := 25_000_000;   -- Hz
    BAUD     : positive := 115_200);     -- bits/s
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;             -- synchronous, active high
    wr      : in  std_logic;             -- load data_in and start (if idle)
    data_in : in  byte_t;
    tx      : out std_logic;             -- serial line, idle high
    busy    : out std_logic);
end entity uart_tx;

architecture rtl of uart_tx is
  constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD;

  signal busy_r  : std_logic := '0';
  signal tx_r    : std_logic := '1';
  signal shift   : byte_t := (others => '1');
  -- 0 = start bit, 1..8 = data bits 0..7, 9 = stop bit.
  signal bit_idx : natural range 0 to 9 := 0;
  signal clk_cnt : natural range 0 to CLKS_PER_BIT - 1 := 0;
begin

  -- Concurrent assertions document an invalid generic combination. They are
  -- accepted by GHDL/Yosys (with formal disabled) and are not simulation-only
  -- constructs.
  assert CLK_FREQ >= BAUD
    report "uart_tx: CLK_FREQ must be >= BAUD" severity failure;
  assert CLKS_PER_BIT >= 2
    report "uart_tx: CLK_FREQ/BAUD must be at least 2" severity failure;

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        busy_r  <= '0';
        tx_r    <= '1';
        shift   <= (others => '1');
        bit_idx <= 0;
        clk_cnt <= 0;
      elsif busy_r = '0' then
        tx_r <= '1';
        if wr = '1' then
          -- Start immediately: the start bit is visible right after this edge
          -- and busy is high for the following cycle (so software polling the
          -- status register cannot overwrite the byte).
          shift   <= data_in;
          bit_idx <= 0;
          clk_cnt <= 0;
          tx_r    <= '0';
          busy_r  <= '1';
        end if;
      else
        if clk_cnt = CLKS_PER_BIT - 1 then
          clk_cnt <= 0;
          if bit_idx = 0 then
            tx_r    <= shift(0);         -- first data bit
            bit_idx <= 1;
          elsif bit_idx <= 7 then
            tx_r    <= shift(bit_idx);   -- data bits 1..7
            bit_idx <= bit_idx + 1;
          elsif bit_idx = 8 then
            tx_r    <= '1';              -- stop bit
            bit_idx <= 9;
          else
            busy_r <= '0';               -- stop bit complete
            tx_r   <= '1';
          end if;
        else
          clk_cnt <= clk_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  tx   <= tx_r;
  busy <= busy_r;

end architecture rtl;
