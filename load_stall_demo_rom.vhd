-- load_stall_demo_rom.vhd : GENERATED from load_stall_demo.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py load_stall_demo.asm --vhdl load_stall_demo_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package load_stall_demo_rom is
  constant PROG : rom_t := (
    x"9205", x"EA40", x"D200", x"8400",
    x"9632", x"D4C0", x"88C0", x"9C34",
    x"8E34", x"F001"
);
end package load_stall_demo_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package load_stall_demo_ram is
  constant INIT : ram_init_t := (
    0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00", 12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00",
    16 => x"00", 17 => x"22"
);
end package load_stall_demo_ram;
