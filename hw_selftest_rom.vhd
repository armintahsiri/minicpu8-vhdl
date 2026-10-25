-- hw_selftest_rom.vhd : GENERATED from hw_selftest.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py hw_selftest.asm --vhdl hw_selftest_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package hw_selftest_rom is
  constant PROG : rom_t := (
    x"9232", x"9430", x"9600", x"9810",
    x"9A31", x"9C10", x"D640", x"E6C1",
    x"E93F", x"C206", x"9810", x"8F80",
    x"DE80", x"8F40", x"F1C3", x"C20D",
    x"8F81", x"DE80", x"8F40", x"F1C3",
    x"C212", x"8F82", x"DE80", x"8F40",
    x"F1C3", x"C217", x"C006"
);
end package hw_selftest_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package hw_selftest_ram is
  constant INIT : ram_init_t := (
    0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00", 12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00",
    16 => x"4F", 17 => x"4B", 18 => x"0A"
);
end package hw_selftest_ram;
