-- alu_compare_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- End-to-end proof of the compare idioms.  For ALL 65,536 (a,b) pairs:
--   SUB through the ALU -> flags -> branch_cond
--   BLT/BGE must match signed comparison
--   BLO/BHS must match unsigned comparison
--   BZ/BNZ must match equality
-- This is the proof that the flag semantics (C=1 means no borrow, signed
-- overflow V) are correctly consumed by the condition unit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity alu_compare_tb is
end entity alu_compare_tb;

architecture sim of alu_compare_tb is
  signal a, b   : std_logic_vector(7 downto 0) := (others => '0');
  signal result : std_logic_vector(7 downto 0);
  signal z, c, n, v : std_logic;
  signal flags  : std_logic_vector(3 downto 0);
  signal cond   : cond_code_t := (others => '0');
  signal taken  : std_logic;
begin

  alu_i : entity work.alu
    port map (a => a, b => b, op => ALU_SUB, result => result,
              z => z, c => c, n => n, v => v);

  flags <= z & n & c & v;

  cond_i : entity work.branch_cond
    port map (flags => flags, cond => cond, taken => taken);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable sa, sb : integer;
    variable exp : std_logic;

    procedure check (name : string; code : cond_code_t; expected : boolean) is
    begin
      cond <= code;
      wait for 1 ns;
      checks := checks + 1;
      if expected then exp := '1'; else exp := '0'; end if;
      if taken /= exp then
        errors := errors + 1;
        report "FAIL " & name & " a=0x" & to_hstring(a) & " b=0x" & to_hstring(b) &
               " got=" & to_string(taken) & " expected=" & to_string(exp)
          severity error;
      end if;
    end procedure;
  begin
    for ia in 0 to 255 loop
      for ib in 0 to 255 loop
        a <= std_logic_vector(to_unsigned(ia, 8));
        b <= std_logic_vector(to_unsigned(ib, 8));
        sa := ia; if sa > 127 then sa := sa - 256; end if;
        sb := ib; if sb > 127 then sb := sb - 256; end if;
        wait for 1 ns;

        check("BLT signed <",  COND_BLT, sa < sb);
        check("BGE signed >=", COND_BGE, sa >= sb);
        check("BLO unsigned <", COND_BCC, ia < ib);
        check("BHS unsigned >=", COND_BCS, ia >= ib);
        check("BZ equal",      COND_BZ,  ia = ib);
        check("BNZ not equal", COND_BNZ, ia /= ib);
      end loop;
    end loop;

    report "alu_compare_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "ALU COMPARE TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "ALU COMPARE TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
