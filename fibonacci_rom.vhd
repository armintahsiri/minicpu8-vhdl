-- fibonacci_rom.vhd : GENERATED from fibonacci.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py fibonacci.asm --vhdl fibonacci_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package fibonacci_rom is
  constant PROG : rom_t := (
    x"8202", x"CF15", x"8C00", x"CF3F",
    x"8203", x"CF15", x"8C00", x"CF3F",
    x"8202", x"8403", x"0650", x"C30F",
    x"D402", x"D603", x"C004", x"8C01",
    x"CF3F", x"8831", x"F103", x"C211",
    x"F001", x"DE05", x"9C00", x"DC06",
    x"8409", x"9600", x"F053", x"C41F",
    x"1250", x"E6C1", x"C01A", x"F0C3",
    x"C127", x"8A08", x"06E8", x"0CC0",
    x"CF3F", x"9C01", x"DC06", x"940A",
    x"9600", x"F053", x"C42E", x"1250",
    x"E6C1", x"C029", x"8C06", x"F183",
    x"C233", x"F0C3", x"C139", x"8A08",
    x"06E8", x"0CC0", x"CF3F", x"9C01",
    x"DC06", x"8A08", x"0268", x"0C40",
    x"CF3F", x"8E05", x"F002", x"8831",
    x"F103", x"C23F", x"DC30", x"F002"
);
end package fibonacci_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package fibonacci_ram is
  constant INIT : ram_init_t := (
    0 => x"20", 1 => x"0A", 2 => x"00", 3 => x"01", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"30", 9 => x"64"
);
end package fibonacci_ram;
