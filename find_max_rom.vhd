-- find_max_rom.vhd : GENERATED from find_max.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py find_max.asm --vhdl find_max_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package find_max_rom is
  constant PROG : rom_t := (
    x"9410", x"9605", x"8280", x"E481",
    x"E6FF", x"8A80", x"F14B", x"C709",
    x"0340", x"E481", x"E6FF", x"C205",
    x"D280", x"F001"
);
end package find_max_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package find_max_ram is
  constant INIT : ram_init_t := (
    0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00", 12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00",
    16 => x"FB", 17 => x"EC", 18 => x"FD", 19 => x"9C", 20 => x"7F"
);
end package find_max_ram;
