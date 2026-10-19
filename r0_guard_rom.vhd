-- r0_guard_rom.vhd : GENERATED from r0_guard.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py r0_guard.asm --vhdl r0_guard_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package r0_guard_rom is
  constant PROG : rom_t := (
    x"9210", x"8040", x"E007", x"D003",
    x"CF06", x"F001", x"8040", x"F002"
);
end package r0_guard_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package r0_guard_ram is
  constant INIT : ram_init_t := (
    0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00", 12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00",
    16 => x"5A"
);
end package r0_guard_ram;
