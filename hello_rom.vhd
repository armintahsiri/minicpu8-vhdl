-- hello_rom.vhd : GENERATED from hello.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py hello.asm --vhdl hello_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package hello_rom is
  constant PROG : rom_t := (
    x"9200", x"9412", x"9A31", x"9C30",
    x"8640", x"8940", x"F103", x"C205",
    x"D780", x"E241", x"B479", x"8940",
    x"F103", x"C20B", x"F001"
);
end package hello_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package hello_ram is
  constant INIT : ram_init_t := (
    0 => x"48", 1 => x"65", 2 => x"6C", 3 => x"6C", 4 => x"6F", 5 => x"2C", 6 => x"20", 7 => x"4D",
    8 => x"69", 9 => x"6E", 10 => x"69", 11 => x"43", 12 => x"50", 13 => x"55", 14 => x"2D", 15 => x"38",
    16 => x"21", 17 => x"0A"
);
end package hello_ram;
