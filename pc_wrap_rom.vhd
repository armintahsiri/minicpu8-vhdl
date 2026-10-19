-- pc_wrap_rom.vhd : GENERATED from pc_wrap.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py pc_wrap.asm --vhdl pc_wrap_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package pc_wrap_rom is
  constant PROG : rom_t := (
    x"C0FD", x"941F", x"F001", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"F000", x"F000", x"F000",
    x"F000", x"9201", x"A002", x"F001"
);
end package pc_wrap_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package pc_wrap_ram is
  constant INIT : ram_init_t := (
    0 => x"00"
);
end package pc_wrap_ram;
