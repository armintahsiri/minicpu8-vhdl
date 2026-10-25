-- ram_wrap_rom.vhd : GENERATED from ram_wrap.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py ram_wrap.asm --vhdl ram_wrap_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package ram_wrap_rom is
  constant PROG : rom_t := (
    x"923F", x"9405", x"D441", x"8641",
    x"F001"
);
end package ram_wrap_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package ram_wrap_ram is
  constant INIT : ram_init_t := (
    0 => x"00"
);
end package ram_wrap_ram;
