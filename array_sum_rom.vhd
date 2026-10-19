-- array_sum_rom.vhd : GENERATED from array_sum.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py array_sum.asm --vhdl array_sum_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package array_sum_rom is
  constant PROG : rom_t := (
    x"9410", x"960A", x"9200", x"8A80",
    x"0268", x"E481", x"E6FF", x"C203",
    x"D280", x"F001"
);
end package array_sum_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package array_sum_ram is
  constant INIT : ram_init_t := (
    0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00", 12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00",
    16 => x"01", 17 => x"02", 18 => x"03", 19 => x"04", 20 => x"05", 21 => x"06", 22 => x"07", 23 => x"08",
    24 => x"09", 25 => x"0A"
);
end package array_sum_ram;
