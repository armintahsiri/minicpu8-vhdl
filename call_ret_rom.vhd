-- call_ret_rom.vhd : GENERATED from call_ret.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py call_ret.asm --vhdl call_ret_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package call_ret_rom is
  constant PROG : rom_t := (
    x"9203", x"9405", x"CF0C", x"D610",
    x"9207", x"9406", x"CF0C", x"D611",
    x"9209", x"CF17", x"D612", x"F001",
    x"9600", x"9808", x"9C01", x"2AB0",
    x"C112", x"06C8", x"6240", x"7480",
    x"E93F", x"C20F", x"F002", x"DE14",
    x"0440", x"CF0C", x"8C14", x"0F80",
    x"F002"
);
end package call_ret_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package call_ret_ram is
  constant INIT : ram_init_t := (
    0 => x"00"
);
end package call_ret_ram;
