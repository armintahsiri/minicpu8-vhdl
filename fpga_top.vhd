-- fpga_top.vhd : synthesizable board wrapper for MiniCPU-8
-- Target board is selected in constraints/<BOARD>.pcf; make bitstream supports
-- hx8k_breakout (default) and icebreaker. The program image is selected at
-- build time through work.fpga_program; no run-time ROM loading is used.
--
-- Reset: the user button is active-low. It asynchronously asserts a two-flop
-- reset synchronizer; release is synchronous, so the CPU sees a clean
-- active-high reset for two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity fpga_top is
  generic (
    CLK_FREQ : positive := 12_000_000;   -- HX8K breakout 12 MHz oscillator
    BAUD     : positive := 115_200;
    LOAD_STALL : boolean := false);      -- EXPERIMENT: sync RAM read latency
  port (
    clk     : in  std_logic;
    rst_n   : in  std_logic;                       -- active-low user button
    uart_tx : out std_logic;                       -- UART TX (header pin H16)
    led     : out std_logic_vector(7 downto 0);    -- 8 user LEDs
    sw      : in  std_logic_vector(7 downto 0));   -- header DIP switches
end entity fpga_top;

architecture rtl of fpga_top is
  signal rst_sync : std_logic_vector(1 downto 0) := "11";
  signal rst      : std_logic;
begin

  -- Asynchronous assert, synchronous de-assert. Both flops reset to 1 so a
  -- board without an external reset still starts in reset.
  process (clk, rst_n) is
  begin
    if rst_n = '0' then
      rst_sync <= "11";
    elsif rising_edge(clk) then
      rst_sync <= rst_sync(0) & '0';
    end if;
  end process;

  rst <= rst_sync(1);

  core : entity work.cpu_top
    generic map (
      PROGRAM  => work.fpga_program.PROGRAM,
      RAM_INIT => work.fpga_program.RAM_INIT,
      CLK_FREQ => CLK_FREQ,
      BAUD     => BAUD,
      DEBUG    => false,
      LOAD_STALL => LOAD_STALL)
    port map (
      clk       => clk,
      rst       => rst,
      halted    => open,
      gpio_in   => sw,
      gpio_out  => led,
      uart_tx   => uart_tx,
      dbg_pc    => open,
      dbg_flags => open,
      dbg_regs  => open,
      dbg_ram   => open);

end architecture rtl;
