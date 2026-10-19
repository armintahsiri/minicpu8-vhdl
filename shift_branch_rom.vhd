-- shift_branch_rom.vhd : GENERATED from shift_branch.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py shift_branch.asm --vhdl shift_branch_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package shift_branch_rom is
  constant PROG : rom_t := (
    x"9203", x"6440", x"6480", x"7680",
    x"5898", x"0B08", x"9C00", x"AB41",
    x"9C3F", x"F001"
);
end package shift_branch_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package shift_branch_ram is
  constant INIT : ram_init_t := (
    0 => x"00"
);
end package shift_branch_ram;
