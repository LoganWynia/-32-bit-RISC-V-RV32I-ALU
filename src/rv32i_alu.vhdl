----------------------------------------------------------------------------------
-- Author:      Logan Wynia
-- Created:     2026-09-14
-- Module:      rv32i_alu - Behavioral
-- Project:     RV32I 32-bit ALU
-- License:     MIT (SPDX-License-Identifier: MIT)
--
-- Description: Purely combinational 32-bit ALU implementing the RV32I
--   register-register integer operations, minimizing hardware by sharing
--   one adder (ADD/SUB/SLT/SLTU) and one barrel shifter (SLL/SRL/SRA).
--   Opcode encoding: op(3) = funct7(5), op(2 downto 0) = funct3.
--
--   op      operation   result
--   ----    ---------   --------------------------------------------
--   "0000"  ADD         a + b
--   "1000"  SUB         a - b
--   "0001"  SLL         a shifted left by b(4 downto 0), zero fill
--   "0010"  SLT         1 when signed(a) < signed(b), else 0
--   "0011"  SLTU        1 when unsigned(a) < unsigned(b), else 0
--   "0100"  XOR         a xor b
--   "0101"  SRL         a shifted right by b(4 downto 0), zero fill
--   "1101"  SRA         a shifted right by b(4 downto 0), sign fill
--   "0110"  OR          a or b
--   "0111"  AND         a and b
--
--   Any other op value outputs 0x00000000 (and therefore zero = 1).
--   zero flag: '1' whenever result is all zeros.
--
-- Simulate (VHDL-2008, GHDL), from the repo root:
--   ghdl -a --std=08 src/rv32i_alu.vhdl tb/rv32i_alu_tb.vhdl
--   ghdl -r --std=08 rv32i_alu_tb
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv32i_alu is
  port (
    a      : in  std_logic_vector(31 downto 0);
    b      : in  std_logic_vector(31 downto 0);
    op     : in  std_logic_vector(3 downto 0);
    result : out std_logic_vector(31 downto 0);
    zero   : out std_logic);
end entity rv32i_alu;

architecture rtl of rv32i_alu is
  constant ZERO32 : std_logic_vector(31 downto 0) := (others => '0');

  -- Result Signal
  signal result_i : std_logic_vector(31 downto 0);

  -- Boolean Operations Signals
  signal xor_r : std_logic_vector(31 downto 0);
  signal or_r : std_logic_vector(31 downto 0);
  signal and_r : std_logic_vector(31 downto 0);

  -- Adder Signals
  signal adder_r : std_logic_vector(33 downto 0);
  signal adder_b : std_logic_vector(31 downto 0);
  signal is_sub : std_logic;

  signal slt_r : std_logic_vector(31 downto 0);
  signal sltu_r : std_logic_vector(31 downto 0);

  -- Shift Signals
  type stage_array is array (0 to 5) of std_logic_vector(31 downto 0);
  signal stage : stage_array;
  signal shifter_in, shifter_out : std_logic_vector(31 downto 0);
  signal shift_fill : std_logic;
  signal is_right_shift : std_logic;

  -- reverse the bit order of a std_logic_vector
  function reverse_bits(v : std_logic_vector) return std_logic_vector is
      variable reversed : std_logic_vector(v'range);
  begin
      for i in 0 to v'length-1 loop
          reversed(v'low + i) := v(v'high - i);
      end loop;
      return reversed;
  end function;

begin

  -- Shifter (shared by SLL, SRL, SRA)
  -- One right-shifter does all three. SLL reverses the input bits, shifts
  -- right, then reverses the result, which is equivalent to a left shift.
  -- Fill bit: SRA (op(3) = '1') replicates a(31); SRL and SLL fill with 0.
  -- (For SLL, op(3) = '0', so the fill is 0 even though the data is reversed.)
  is_right_shift <= op(2);
  shift_fill     <= op(3) and a(31);
  shifter_in     <= a when is_right_shift = '1' else reverse_bits(a);
  stage(0)       <= shifter_in;

  -- Five stages: stage k shifts right by 2**k if b(k) = '1', else passes
  -- through. Together they shift by any amount 0..31 (b(4 downto 0)).
  gen_stages : for k in 0 to 4 generate
      constant SHIFT_AMT : integer := 2**k;
  begin
      -- Upper SHIFT_AMT bits become the fill bit; the rest move right.
      stage(k+1) <= stage(k) when b(k) = '0' else
                    (SHIFT_AMT-1 downto 0 => shift_fill) &
                    stage(k)(31 downto SHIFT_AMT);
  end generate gen_stages;

  shifter_out <= stage(5) when is_right_shift = '1' else reverse_bits(stage(5));


  -- Adder (shared by ADD, SUB, SLT, SLTU)
  -- Subtract is a + ~b + 1. The +1 is injected as a carry-in: a 0 is
  -- prepended and is_sub is appended to BOTH operands, so bit 0 computes
  -- is_sub + is_sub, which carries into bit 1 only when is_sub = '1'.
  --   adder_r(33)          carry-out
  --   adder_r(32 downto 1) 32-bit sum/difference
  --   adder_r(32)          sign bit of the difference
  is_sub  <= op(3) or op(1);              -- SUB (1000), SLT (0010), SLTU (0011)
  adder_b <= b when is_sub = '0' else not b;
  adder_r <= std_logic_vector(unsigned('0' & a & is_sub)
                            + unsigned('0' & adder_b & is_sub));

  -- SLT: if the signs match, a - b cannot overflow, so the sign of the
  -- difference is correct. If the signs differ, the difference may overflow,
  -- but the answer is simply "a is negative".
  slt_r <= (0 => a(31), others => '0') when ((a(31) xor b(31)) = '1')
      else (0 => adder_r(32), others => '0');

  -- SLTU: a + ~b + 1 produces a carry-out exactly when a >= b (unsigned),
  -- so no carry means a < b.
  sltu_r <= (0 => '1', others => '0') when adder_r(33) = '0'
       else (others => '0');


  -- Boolean Operations
  --   "0100"  XOR         
  xor_r <= a xor b;
  --   "0110"  OR         
  or_r <= a or b;
  --   "0111"  AND
  and_r <= a and b;

  with op select result_i <=
    adder_r(32 downto 1)  when "0000" | "1000",
    slt_r  when "0010",
    sltu_r  when "0011",
    xor_r  when "0100",
    shifter_out when "0101" | "1101" | "0001",
    or_r  when "0110",
    and_r  when "0111",
    ZERO32 when others;
  result <= result_i;

  -- Zero Flag
  zero <= '1' when result_i = ZERO32 else '0';
end architecture rtl;
