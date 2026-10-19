-- unsigned_vs_signed_rom.vhd : GENERATED from unsigned_vs_signed.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py unsigned_vs_signed.asm --vhdl unsigned_vs_signed_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package unsigned_vs_signed_rom is
  constant PROG : rom_t := (
    x"923E", x"9401", x"F053", x"C407",
    x"C309", x"9600", x"C00A", x"9601",
    x"C00A", x"9602", x"F053", x"C70F",
    x"C811", x"9800", x"C012", x"9803",
    x"C012", x"9804", x"F001"
);
end package unsigned_vs_signed_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package unsigned_vs_signed_ram is
  constant INIT : ram_init_t := (
    0 => x"00"
);
end package unsigned_vs_signed_ram;
