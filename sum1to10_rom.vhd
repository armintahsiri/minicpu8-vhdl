-- sum1to10_rom.vhd : GENERATED from sum1to10.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py sum1to10.asm --vhdl sum1to10_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package sum1to10_rom is
  constant PROG : rom_t := (
    x"9200", x"9401", x"960B", x"9801",
    x"0250", x"04A0", x"B6BD", x"D000"
);
end package sum1to10_rom;
