-- uart_rx_model.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Independent oversampling 8N1 receiver used to check the serial output of
-- uart_tx / cpu_top. It samples at the centre of the start, data and stop bits
-- using its own state machine (not the DUT's internal signals), verifies the
-- framing bits, and stores received bytes LSB-first in a packed vector.
-- `count` is the number of complete, well-framed bytes; `errors` counts
-- framing and overflow errors.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity uart_rx_model is
  generic (
    CLKS_PER_BIT : positive := 10;
    MAX_BYTES    : positive := 8);
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    serial : in  std_logic;
    data   : out std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
    count  : out natural range 0 to MAX_BYTES;
    errors : out natural);
end entity uart_rx_model;

architecture sim of uart_rx_model is
  type rx_state_t is (IDLE, RX_START, RX_DATA, RX_STOP);

  signal state    : rx_state_t := IDLE;
  signal timer    : natural range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx  : natural range 0 to 7 := 0;
  signal shift    : byte_t := (others => '0');
  signal data_r   : std_logic_vector(MAX_BYTES * 8 - 1 downto 0) := (others => '0');
  signal count_r  : natural range 0 to MAX_BYTES := 0;
  signal errors_r : natural := 0;
begin

  assert CLKS_PER_BIT >= 4
    report "uart_rx_model: CLKS_PER_BIT must be at least 4 for centre sampling"
    severity failure;

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state    <= IDLE;
        timer    <= 0;
        bit_idx  <= 0;
        shift    <= (others => '0');
        data_r   <= (others => '0');
        count_r  <= 0;
        errors_r <= 0;
      else
        case state is
          when IDLE =>
            if serial = '0' then
              -- Wait half a bit to reach the centre of the start bit. The
              -- extra -2 accounts for the edge on which the start is detected
              -- and the non-blocking timer update.
              state <= RX_START;
              timer <= CLKS_PER_BIT / 2 - 2;
            end if;

          when RX_START =>
            if timer = 0 then
              if serial = '0' then
                state   <= RX_DATA;
                bit_idx <= 0;
                timer   <= CLKS_PER_BIT - 1;
              else
                errors_r <= errors_r + 1;   -- false start
                state    <= IDLE;
              end if;
            else
              timer <= timer - 1;
            end if;

          when RX_DATA =>
            if timer = 0 then
              shift(bit_idx) <= serial;     -- LSB first
              if bit_idx = 7 then
                state <= RX_STOP;
                timer <= CLKS_PER_BIT - 1;
              else
                bit_idx <= bit_idx + 1;
                timer   <= CLKS_PER_BIT - 1;
              end if;
            else
              timer <= timer - 1;
            end if;

          when RX_STOP =>
            if timer = 0 then
              if serial = '1' then
                if count_r < MAX_BYTES then
                  data_r((count_r + 1) * 8 - 1 downto count_r * 8) <= shift;
                  count_r <= count_r + 1;
                else
                  errors_r <= errors_r + 1; -- too many bytes
                end if;
              else
                errors_r <= errors_r + 1;   -- framing error
              end if;
              state <= IDLE;
            else
              timer <= timer - 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  data   <= data_r;
  count  <= count_r;
  errors <= errors_r;

end architecture sim;
