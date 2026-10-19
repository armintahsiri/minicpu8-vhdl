-- alu.vhd : 8-bit combinational ALU for MiniCPU-8
-- Flags: Z (zero), C (carry; for SUB: C=1 means NO borrow), N (negative), V (signed overflow)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.minicpu_pkg.all;

entity alu is
  port (
    a      : in  std_logic_vector(7 downto 0);  -- operand A (rs1)
    b      : in  std_logic_vector(7 downto 0);  -- operand B (rs2 or immediate)
    op     : in  alu_op_t;
    result : out std_logic_vector(7 downto 0);
    z      : out std_logic;
    c      : out std_logic;
    n      : out std_logic;
    v      : out std_logic
  );
end entity alu;

architecture rtl of alu is
begin

  process (all)
    variable ua, ub : unsigned(7 downto 0);
    variable sum    : unsigned(8 downto 0);  -- 9 bits: bit 8 is the carry out
    variable res    : unsigned(7 downto 0);
    variable cf, vf : std_logic;
  begin
    -- Default values for EVERY variable: prevents inferred latches
    ua  := unsigned(a);
    ub  := unsigned(b);
    sum := (others => '0');
    res := (others => '0');
    cf  := '0';
    vf  := '0';

    case op is
      when ALU_ADD =>
        sum := ('0' & ua) + ('0' & ub);
        res := sum(7 downto 0);
        cf  := sum(8);
        -- overflow: operands have the same sign, result sign differs
        vf  := (a(7) xnor b(7)) and (a(7) xor res(7));

      when ALU_SUB =>
        -- A - B = A + (not B) + 1  (two's complement; same adder as ADD)
        sum := ('0' & ua) + ('0' & (not ub)) + 1;
        res := sum(7 downto 0);
        cf  := sum(8);                      -- 1 = no borrow (ARM convention)
        -- overflow: operands have different signs, result sign differs from A
        vf  := (a(7) xor b(7)) and (a(7) xor res(7));

      when ALU_AND    => res := ua and ub;   -- C and V cleared
      when ALU_OR     => res := ua or ub;
      when ALU_XOR    => res := ua xor ub;
      when ALU_NOT    => res := not ua;      -- B ignored
      when ALU_SHL =>
        res := ua(6 downto 0) & '0';        -- B ignored; 1-bit logical left
        cf  := ua(7);                       -- bit shifted out
        vf  := ua(7) xor res(7);            -- sign changed
      when ALU_SHR =>
        res := '0' & ua(7 downto 1);        -- B ignored; 1-bit logical right
        cf  := ua(0);                       -- bit shifted out
        vf  := '0';                         -- logical shift never overflows
      when ALU_PASS_B => res := ub;          -- used by LOADI (MOV is ADD with R0)
    end case;

    result <= std_logic_vector(res);
    c      <= cf;
    v      <= vf;
    n      <= res(7);
    if res = 0 then z <= '1'; else z <= '0'; end if;
  end process;

end architecture rtl;
