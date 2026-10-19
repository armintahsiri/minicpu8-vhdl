-- gpio_demo_rom.vhd : GENERATED from gpio_demo.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py gpio_demo.asm --vhdl gpio_demo_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package gpio_demo_rom is
  constant PROG : rom_t := (
    x"F000", x"F000", x"8233", x"4440",
    x"D432", x"8632", x"F001"
);
end package gpio_demo_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package gpio_demo_ram is
  constant INIT : ram_init_t := (
    0 => x"00"
);
end package gpio_demo_ram;
