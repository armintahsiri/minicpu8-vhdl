-- register_file.vhd : 8 x 8-bit register file for MiniCPU-8
-- Two asynchronous read ports, one synchronous write port.
-- R0 is hardwired to zero: reads return 0x00 and writes are ignored.
-- The dbg port exposes the whole file for testbenches (wires only).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity register_file is
  port (
    clk    : in  std_logic;
    raddr1 : in  regsel_t;  -- read port 1 (rs field)
    raddr2 : in  regsel_t;  -- read port 2 (rt or rd field)
    waddr  : in  regsel_t;  -- write port (rd field)
    wdata  : in  byte_t;
    we     : in  std_logic;
    rd1    : out byte_t;
    rd2    : out byte_t;
    dbg    : out regfile_t);
end entity register_file;

architecture rtl of register_file is
  -- zero-initialized for clean simulations; no architectural reset
  signal mem : regfile_t := (others => (others => '0'));
begin

  write_p : process (clk) is
  begin
    if rising_edge(clk) then
      if we = '1' and waddr /= "000" then   -- writes to R0 ignored
        mem(to_integer(unsigned(waddr))) <= wdata;
      end if;
    end if;
  end process;

  -- Asynchronous reads; R0 always reads zero. Reading a register in the
  -- same cycle it is written returns the OLD value (visible after the edge).
  -- The is_x guards avoid numeric_std metavalue warnings in the first delta
  -- cycle, before the instruction word has settled.
  read_p : process (all) is
  begin
    rd1 <= (others => '0');
    rd2 <= (others => '0');
    if not is_x(raddr1) and raddr1 /= "000" then
      rd1 <= mem(to_integer(unsigned(raddr1)));
    end if;
    if not is_x(raddr2) and raddr2 /= "000" then
      rd2 <= mem(to_integer(unsigned(raddr2)));
    end if;
  end process;

  dbg <= mem;   -- dbg(0) stays zero because mem(0) is never written

end architecture rtl;
