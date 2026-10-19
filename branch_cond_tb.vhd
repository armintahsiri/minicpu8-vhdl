-- branch_cond_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Exhaustive: all 16 flag combinations x all 16 condition codes, compared
-- against an independent boolean reference implementation.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity branch_cond_tb is
end entity branch_cond_tb;

architecture sim of branch_cond_tb is
  signal flags : std_logic_vector(3 downto 0) := (others => '0');
  signal cond  : cond_code_t := (others => '0');
  signal taken : std_logic;

  function reference (f : std_logic_vector(3 downto 0);
                      cc : integer) return std_logic is
    variable z, n, c, v : boolean;
  begin
    z := f(3) = '1';
    n := f(2) = '1';
    c := f(1) = '1';
    v := f(0) = '1';
    case cc is
      when 0  => return '1';                 -- JMP
      when 1  => if z then return '1'; else return '0'; end if;
      when 2  => if not z then return '1'; else return '0'; end if;
      when 3  => if c then return '1'; else return '0'; end if;
      when 4  => if not c then return '1'; else return '0'; end if;
      when 5  => if n then return '1'; else return '0'; end if;
      when 6  => if not n then return '1'; else return '0'; end if;
      when 7  => if n xor v then return '1'; else return '0'; end if;
      when 8  => if not (n xor v) then return '1'; else return '0'; end if;
      when 15 => return '1';                 -- CALL (always)
      when others => return '0';             -- reserved
    end case;
  end function;
begin

  dut : entity work.branch_cond
    port map (flags => flags, cond => cond, taken => taken);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;
    variable exp : std_logic;
  begin
    for f in 0 to 15 loop
      for cc in 0 to 15 loop
        flags <= std_logic_vector(to_unsigned(f, 4));
        cond  <= std_logic_vector(to_unsigned(cc, 4));
        wait for 1 ns;
        checks := checks + 1;
        exp := reference(std_logic_vector(to_unsigned(f, 4)), cc);
        if taken /= exp then
          errors := errors + 1;
          report "FAIL flags=ZNCV" & to_string(flags) &
                 " cond=" & integer'image(cc) &
                 " got=" & to_string(taken) & " expected=" & to_string(exp)
            severity error;
        end if;
      end loop;
    end loop;

    report "branch_cond_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "BRANCH COND TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "BRANCH COND TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
