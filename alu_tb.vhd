-- alu_tb.vhd : *** TESTBENCH ONLY - NOT SYNTHESIZABLE ***
-- Self-checking: directed tests + exhaustive ADD/SUB/AND/OR/XOR/NOT/PASS_B
-- (all 65536 operand pairs) and exhaustive SHL/SHR (all 256 A values),
-- checked against an independent integer/signed reference model.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.minicpu_pkg.all;

entity alu_tb is
end entity alu_tb;

architecture sim of alu_tb is
  signal a, b   : std_logic_vector(7 downto 0) := (others => '0');
  signal op     : alu_op_t := ALU_ADD;
  signal result : std_logic_vector(7 downto 0);
  signal z, c, n, v : std_logic;
begin

  dut : entity work.alu
    port map (a => a, b => b, op => op, result => result, z => z, c => c, n => n, v => v);

  stim : process
    variable errors : natural := 0;
    variable checks : natural := 0;

    -- Apply inputs, wait, compare all 5 outputs with expected values.
    procedure check (name : string; o : alu_op_t; ia, ib, er : integer;
                     ez, ec, en, ev : std_logic) is
    begin
      a  <= std_logic_vector(to_unsigned(ia, 8));
      b  <= std_logic_vector(to_unsigned(ib, 8));
      op <= o;
      wait for 1 ns;
      checks := checks + 1;
      if result /= std_logic_vector(to_unsigned(er, 8)) or
         z /= ez or c /= ec or n /= en or v /= ev then
        errors := errors + 1;
        report "FAIL " & name & " a=0x" & to_hstring(a) & " b=0x" & to_hstring(b) &
               " got res=0x" & to_hstring(result) & " ZCNV=" & to_string(z) & to_string(c) &
               to_string(n) & to_string(v) &
               " expected res=0x" & to_hstring(to_unsigned(er, 8)) & " ZCNV=" &
               to_string(ez) & to_string(ec) & to_string(en) & to_string(ev)
          severity error;
      end if;
    end procedure;

    -- helpers for the exhaustive reference model
    function sgn (x : integer) return integer is
    begin
      if x > 127 then return x - 256; else return x; end if;
    end function;
    function bit_of (cond : boolean) return std_logic is
    begin
      if cond then return '1'; else return '0'; end if;
    end function;

    variable full, ssum, r : integer;
  begin
    -- ---------------- ADD (name, op, a, b, result, Z, C, N, V) ----------------
    check("ADD 5+3",          ALU_ADD, 16#05#, 16#03#, 16#08#, '0','0','0','0');
    check("ADD 0+0 zero",     ALU_ADD, 16#00#, 16#00#, 16#00#, '1','0','0','0');
    check("ADD FF+01 carry",  ALU_ADD, 16#FF#, 16#01#, 16#00#, '1','1','0','0');
    check("ADD 7F+01 ovf",    ALU_ADD, 16#7F#, 16#01#, 16#80#, '0','0','1','1');
    check("ADD 80+80 ovf+c",  ALU_ADD, 16#80#, 16#80#, 16#00#, '1','1','0','1');
    check("ADD FF+FF -1+-1",  ALU_ADD, 16#FF#, 16#FF#, 16#FE#, '0','1','1','0');
    check("ADD 7F+7F ovf",    ALU_ADD, 16#7F#, 16#7F#, 16#FE#, '0','0','1','1');
    -- ---------------- SUB (C=1 means no borrow) ----------------
    check("SUB 5-3",          ALU_SUB, 16#05#, 16#03#, 16#02#, '0','1','0','0');
    check("SUB 3-5 borrow",   ALU_SUB, 16#03#, 16#05#, 16#FE#, '0','0','1','0');
    check("SUB 5-5 zero",     ALU_SUB, 16#05#, 16#05#, 16#00#, '1','1','0','0');
    check("SUB 0-1",          ALU_SUB, 16#00#, 16#01#, 16#FF#, '0','0','1','0');
    check("SUB 80-01 ovf",    ALU_SUB, 16#80#, 16#01#, 16#7F#, '0','1','0','1');
    check("SUB 7F-FF ovf",    ALU_SUB, 16#7F#, 16#FF#, 16#80#, '0','0','1','1');
    check("SUB 00-80 ovf",    ALU_SUB, 16#00#, 16#80#, 16#80#, '0','0','1','1');
    -- ---------------- Logic (C and V must be 0 even if inputs "would carry") ----------------
    check("AND F0&3C",        ALU_AND, 16#F0#, 16#3C#, 16#30#, '0','0','0','0');
    check("AND F0&0F zero",   ALU_AND, 16#F0#, 16#0F#, 16#00#, '1','0','0','0');
    check("AND FF&80 neg",    ALU_AND, 16#FF#, 16#80#, 16#80#, '0','0','1','0');
    check("OR  F0|0F",        ALU_OR,  16#F0#, 16#0F#, 16#FF#, '0','0','1','0');
    check("OR  00|00 zero",   ALU_OR,  16#00#, 16#00#, 16#00#, '1','0','0','0');
    check("OR  10|01",        ALU_OR,  16#10#, 16#01#, 16#11#, '0','0','0','0');
    check("NOT 00",           ALU_NOT, 16#00#, 16#77#, 16#FF#, '0','0','1','0');  -- B ignored
    check("NOT FF zero",      ALU_NOT, 16#FF#, 16#00#, 16#00#, '1','0','0','0');
    check("NOT AA",           ALU_NOT, 16#AA#, 16#00#, 16#55#, '0','0','0','0');
    -- ---------------- XOR (C and V must be 0) ----------------
    check("XOR F0^5A",        ALU_XOR, 16#F0#, 16#5A#, 16#AA#, '0','0','1','0');
    check("XOR FF^FF zero",   ALU_XOR, 16#FF#, 16#FF#, 16#00#, '1','0','0','0');
    check("XOR 00^01",        ALU_XOR, 16#00#, 16#01#, 16#01#, '0','0','0','0');
    -- ---------------- SHL (C = old bit7, V = sign changed, B ignored) ----------------
    check("SHL 01 -> 02",     ALU_SHL, 16#01#, 16#77#, 16#02#, '0','0','0','0');
    check("SHL 40 -> 80 V=1", ALU_SHL, 16#40#, 16#00#, 16#80#, '0','0','1','1');
    check("SHL 80 -> 00 C=1", ALU_SHL, 16#80#, 16#00#, 16#00#, '1','1','0','1');
    check("SHL C0 -> 80 C=1", ALU_SHL, 16#C0#, 16#00#, 16#80#, '0','1','1','0');
    -- ---------------- SHR (C = old bit0, V = 0, B ignored) ----------------
    check("SHR 01 -> 00 C=1", ALU_SHR, 16#01#, 16#77#, 16#00#, '1','1','0','0');
    check("SHR FF -> 7F C=1", ALU_SHR, 16#FF#, 16#00#, 16#7F#, '0','1','0','0');
    check("SHR 80 -> 40",     ALU_SHR, 16#80#, 16#00#, 16#40#, '0','0','0','0');
    -- ---------------- PASS_B (A ignored) ----------------
    check("PASS 42",          ALU_PASS_B, 16#FF#, 16#42#, 16#42#, '0','0','0','0');
    check("PASS 00 zero",     ALU_PASS_B, 16#FF#, 16#00#, 16#00#, '1','0','0','0');
    check("PASS 80 neg",      ALU_PASS_B, 16#00#, 16#80#, 16#80#, '0','0','1','0');

    -- ---------------- Exhaustive ADD/SUB vs independent reference ----------------
    for ia in 0 to 255 loop
      for ib in 0 to 255 loop
        -- ADD
        full := ia + ib;
        ssum := sgn(ia) + sgn(ib);
        r    := full mod 256;
        check("EXH ADD", ALU_ADD, ia, ib, r,
              bit_of(r = 0), bit_of(full > 255), bit_of(r >= 128),
              bit_of(ssum > 127 or ssum < -128));
        -- SUB
        full := ia - ib;
        ssum := sgn(ia) - sgn(ib);
        r    := (full + 256) mod 256;
        check("EXH SUB", ALU_SUB, ia, ib, r,
              bit_of(r = 0), bit_of(ia >= ib), bit_of(r >= 128),
              bit_of(ssum > 127 or ssum < -128));
        -- AND / OR / XOR: logic result, C=0, V=0  (bitwise via unsigned)
        r := to_integer(to_unsigned(ia, 8) and to_unsigned(ib, 8));
        check("EXH AND", ALU_AND, ia, ib, r, bit_of(r = 0), '0', bit_of(r >= 128), '0');
        r := to_integer(to_unsigned(ia, 8) or to_unsigned(ib, 8));
        check("EXH OR",  ALU_OR,  ia, ib, r, bit_of(r = 0), '0', bit_of(r >= 128), '0');
        r := to_integer(to_unsigned(ia, 8) xor to_unsigned(ib, 8));
        check("EXH XOR", ALU_XOR, ia, ib, r, bit_of(r = 0), '0', bit_of(r >= 128), '0');
        -- NOT (B irrelevant): r = bitwise not ia
        r := to_integer(not to_unsigned(ia, 8));
        check("EXH NOT", ALU_NOT, ia, ib, r, bit_of(r = 0), '0', bit_of(r >= 128), '0');
        -- PASS_B (A irrelevant): r = ib
        check("EXH PASS", ALU_PASS_B, ia, ib, ib, bit_of(ib = 0), '0',
              bit_of(ib >= 128), '0');
      end loop;
    end loop;

    -- ---------------- Exhaustive SHL/SHR (B ignored, all 256 A values) ----------------
    for ia in 0 to 255 loop
      -- SHL: r = (2*ia) mod 256, C = old bit7, V = old bit7 xor new bit7 (= old bit6)
      r := (2 * ia) mod 256;
      check("EXH SHL", ALU_SHL, ia, 16#5A#, r, bit_of(r = 0),
            bit_of(ia >= 128), bit_of(r >= 128),
            bit_of(((ia / 128) mod 2) /= ((ia / 64) mod 2)));
      -- SHR: r = ia / 2, C = old bit0, V = 0
      r := ia / 2;
      check("EXH SHR", ALU_SHR, ia, 16#5A#, r, bit_of(r = 0),
            bit_of(ia mod 2 = 1), bit_of(r >= 128), '0');
    end loop;

    report "alu_tb: " & integer'image(checks) & " checks, " &
           integer'image(errors) & " errors";
    if errors = 0 then
      report "ALU TESTBENCH: ALL TESTS PASSED";
      finish;
    else
      report "ALU TESTBENCH: FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
