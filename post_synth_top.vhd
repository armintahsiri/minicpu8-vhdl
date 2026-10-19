-- post_synth_top.vhd : synthesizable verification wrapper (not a board top)
-- Exposes cpu_top's debug ports so a post-synthesis netlist can be simulated
-- and compared byte-for-byte with the golden model. PROGRAM/RAM_INIT come from
-- the generated work.fpga_program package, selected with make PROGRAM=...
-- DEBUG=true keeps the full data-RAM view available in the netlist.
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

entity post_synth_top is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    halted    : out std_logic;
    gpio_in   : in  byte_t;
    gpio_out  : out byte_t;
    uart_tx   : out std_logic;
    dbg_pc    : out byte_t;
    dbg_flags : out std_logic_vector(3 downto 0);
    dbg_regs  : out regfile_t;
    dbg_ram   : out ram_t);
end entity post_synth_top;

architecture rtl of post_synth_top is
begin
  core : entity work.cpu_top
    generic map (
      PROGRAM  => work.fpga_program.PROGRAM,
      RAM_INIT => work.fpga_program.RAM_INIT,
      CLK_FREQ => 1_000_000,
      BAUD     => 100_000,
      DEBUG    => true)
    port map (
      clk       => clk,
      rst       => rst,
      halted    => halted,
      gpio_in   => gpio_in,
      gpio_out  => gpio_out,
      uart_tx   => uart_tx,
      dbg_pc    => dbg_pc,
      dbg_flags => dbg_flags,
      dbg_regs  => dbg_regs,
      dbg_ram   => dbg_ram);
end architecture rtl;
