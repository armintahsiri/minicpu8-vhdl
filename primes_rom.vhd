-- primes_rom.vhd : GENERATED from primes.asm by tools/assembler.py
-- DO NOT EDIT -- regenerate with: python3 tools/assembler.py primes.asm --vhdl primes_rom.vhd
library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package primes_rom is
  constant PROG : rom_t := (
    x"8202", x"9402", x"D403", x"8403",
    x"8202", x"F08B", x"C311", x"8802",
    x"F113", x"C40C", x"1910", x"C008",
    x"F103", x"C115", x"E481", x"D403",
    x"C003", x"8202", x"CF20", x"8C00",
    x"CF4A", x"8202", x"E241", x"C31A",
    x"D202", x"C000", x"8C01", x"CF4A",
    x"8831", x"F103", x"C21C", x"F001",
    x"DE05", x"9C00", x"DC06", x"8409",
    x"9600", x"F053", x"C42A", x"1250",
    x"E6C1", x"C025", x"F0C3", x"C132",
    x"8A08", x"06E8", x"0CC0", x"CF4A",
    x"9C01", x"DC06", x"940A", x"9600",
    x"F053", x"C439", x"1250", x"E6C1",
    x"C034", x"8C06", x"F183", x"C23E",
    x"F0C3", x"C144", x"8A08", x"06E8",
    x"0CC0", x"CF4A", x"9C01", x"DC06",
    x"8A08", x"0268", x"0C40", x"CF4A",
    x"8E05", x"F002", x"8831", x"F103",
    x"C24A", x"DC30", x"F002"
);
end package primes_rom;

library ieee;
use ieee.std_logic_1164.all;
use work.minicpu_pkg.all;

package primes_ram is
  constant INIT : ram_init_t := (
    0 => x"20", 1 => x"0A", 2 => x"02", 3 => x"00", 4 => x"00", 5 => x"00", 6 => x"00", 7 => x"00",
    8 => x"30", 9 => x"64"
);
end package primes_ram;
