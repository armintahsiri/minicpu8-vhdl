-- io_cpu_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- CPU-level MMIO test: LOAD/STORE through the address decoder to UART, GPIO,
-- the cycle counter and a reserved address; checks that MMIO stores do not
-- touch data RAM. The UART bytes are captured by an independent receiver.
-- Program (hand-assembled, 21 words):
--   write 0x0A; immediately write 0x0B while busy (ignored);
--   write GPIO_OUT=0x15; read back; read GPIO_IN into RAM[0]; poll UART;
--   write 0x0B; read CYCLE_COUNT_LO; read reserved 0xFC; halt.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity io_cpu_tb is
end entity io_cpu_tb;

architecture sim of io_cpu_tb is
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal halted   : std_logic;
  signal pc       : byte_t;
  signal flags    : std_logic_vector(3 downto 0);
  signal regs     : regfile_t;
  signal ram      : ram_t;
  signal gpio_in  : byte_t := x"C3";
  signal gpio_out : byte_t;
  signal uart_tx  : std_logic;

  constant PROG : rom_t(0 to 21) := (
    0  => x"9231",   -- loadi r1, UART_STATUS
    1  => x"9430",   -- loadi r2, UART_TX
    2  => x"9632",   -- loadi r3, GPIO_OUT
    3  => x"9833",   -- loadi r4, GPIO_IN
    4  => x"9A34",   -- loadi r5, CYCLE_COUNT_LO
    5  => x"9C0A",   -- loadi r6, 10
    6  => x"DC80",   -- store r6, [r2+0]  -> UART 0x0A
    7  => x"9E0B",   -- loadi r7, 11
    8  => x"DE80",   -- store r7, [r2+0]  -> ignored (busy)
    9  => x"9E15",   -- loadi r7, 21
    10 => x"DEC0",   -- store r7, [r3+0]  -> GPIO_OUT
    11 => x"8CC0",   -- load r6, [r3+0]   -> readback
    12 => x"8F00",   -- load r7, [r4+0]   -> GPIO_IN
    13 => x"DE00",   -- store r7, [r0+0]  -> RAM[0]
    14 => x"8C40",   -- poll: load r6, [r1+0]
    15 => x"F183",   -- cmp r6, r0        (LOAD does not write flags)
    16 => x"C20E",   -- bnz poll
    17 => x"9C0B",   -- loadi r6, 11
    18 => x"DC80",   -- store r6, [r2+0]  -> UART 0x0B
    19 => x"8D40",   -- load r6, [r5+0]   -> cycle counter low
    20 => x"8E3C",   -- load r7, [r0-4]   -> reserved 0xFC reads 0
    21 => x"F001");  -- halt

  constant RAM_INIT : ram_init_t(0 to 0) := (0 => x"00");
  constant MAX_CYCLES : natural := 300;
  constant CLKS_PER_BIT : natural := 10;
  constant BIT_TIME : time := 10 ns * CLKS_PER_BIT;

  signal rx_data   : std_logic_vector(31 downto 0);
  signal rx_count  : natural range 0 to 4;
  signal rx_errors : natural;
  signal done : boolean := false;
begin

  clk <= not clk after 5 ns;

  dut : entity work.cpu_top
    generic map (PROGRAM => PROG, RAM_INIT => RAM_INIT,
                 CLK_FREQ => 1_000_000, BAUD => 100_000)
    port map (clk => clk, rst => rst, halted => halted, gpio_in => gpio_in,
              gpio_out => gpio_out, uart_tx => uart_tx, dbg_pc => pc,
              dbg_flags => flags, dbg_regs => regs, dbg_ram => ram);

  rx : entity work.uart_rx_model
    generic map (CLKS_PER_BIT => CLKS_PER_BIT, MAX_BYTES => 4)
    port map (clk => clk, rst => rst, serial => uart_tx, data => rx_data,
              count => rx_count, errors => rx_errors);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable cycles : natural := 0;

    procedure expect (name : string; cond : boolean) is
    begin
      checks := checks + 1;
      if not cond then
        errors := errors + 1;
        report "IO CPU FAIL: " & name severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until falling_edge(clk);
    rst <= '0';

    while halted /= '1' loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      if cycles > MAX_CYCLES then
        report "IO CPU: CYCLE BUDGET EXCEEDED" severity failure;
      end if;
      wait for 1 ns;
    end loop;
    wait for 1 ns;

    -- The last byte may still be on the wire when the CPU halts: 0x0B starts
    -- at cycle 110 and finishes at 210, HALT is reached at cycle 113.
    wait for 12 * BIT_TIME;
    wait for 1 ns;

    expect("halted", halted = '1');
    expect("cycle count 114", cycles = 114);
    expect("PC 21", pc = x"15");
    expect("r1 UART_STATUS address", regs(1) = x"F1");
    expect("r2 UART_TX address", regs(2) = x"F0");
    expect("r3 GPIO_OUT address", regs(3) = x"F2");
    expect("r4 GPIO_IN address", regs(4) = x"F3");
    expect("r5 CYCLE_COUNT address", regs(5) = x"F4");
    expect("r6 cycle counter low byte (112)", regs(6) = x"70");
    expect("r7 reserved read 0", regs(7) = x"00");
    expect("GPIO_OUT = 0x15", gpio_out = x"15");
    expect("GPIO_IN stored to RAM[0]", ram(0) = x"C3");
    expect("MMIO store did not write RAM[0xF0]", ram(16#F0#) = x"00");
    expect("UART captured two bytes", rx_count = 2);
    expect("UART byte 0 = 0x0A", rx_data(7 downto 0) = x"0A");
    expect("UART byte 1 = 0x0B", rx_data(15 downto 8) = x"0B");
    expect("UART no framing errors", rx_errors = 0);
    expect("UART line idle", uart_tx = '1');

    report "io_cpu_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors, " & integer'image(cycles) &
           " cycles";
    if errors = 0 then
      report "IO CPU TESTBENCH: ALL TESTS PASSED";
      done <= true;
    else
      report "IO CPU TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 200 us;
    report "IO CPU TESTBENCH: GLOBAL WATCHDOG TIMEOUT" severity failure;
    wait;
  end process;

  finisher : process
  begin
    wait until done;
    finish;
  end process;

end architecture sim;
