----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/22/2026 06:43:18 PM
-- Design Name: 
-- Module Name: rv32i_alu_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: Self-checking testbench for the 32-bit RV32I ALU (rv32i_alu).
--              For each of the 10 ALU operations it applies a handful of
--              directed corner-case vectors plus several pseudo-random
--              vectors, compares the ALU's result and zero flag against a
--              behavioral reference model, and prints a per-operation
--              PASS summary and an overall score.
-- 
-- Dependencies: rv32i_alu.vhdl (entity work.rv32i_alu)
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--   Compile/run with GHDL (VHDL-2008):
--     ghdl -a --std=08 rv32i_alu.vhdl rv32i_alu_tb.vhdl
--     ghdl -r --std=08 rv32i_alu_tb
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;  -- for randomized test vectors (uniform procedure)


entity rv32i_alu_tb is
--  Port ( );  -- a testbench has no ports
end rv32i_alu_tb;

architecture Behavioral of rv32i_alu_tb is
    -- Signals that connect to the ALU under test
    signal a, b   : std_logic_vector(31 downto 0) := (others => '0');  -- operands
    signal op     : std_logic_vector(3 downto 0)  := (others => '0');  -- operation select
    signal result : std_logic_vector(31 downto 0);                     -- ALU output
    signal zero   : std_logic;                                         -- '1' when result = 0

    -- List of every opcode the ALU supports, in the order they are tested.
    -- Encoding: op(3) = funct7 bit 5, op(2 downto 0) = funct3 (RV32I R-type).
    type op_array_t is array (0 to 9) of std_logic_vector(3 downto 0);
    constant OP_LIST : op_array_t :=
        ("0000", "1000", "0001", "0010", "0011",
         "0100", "0101", "1101", "0110", "0111");

    -- Human-readable names, one per entry in OP_LIST (same index order).
    -- Each name is padded with spaces to exactly 5 characters so it fits
    -- the fixed-length string type and the report columns line up.
    type name_array_t is array (0 to 9) of string(1 to 5);
    constant OP_NAMES : name_array_t :=
        ("ADD  ", "SUB  ", "SLL  ", "SLT  ", "SLTU ",
         "XOR  ", "SRL  ", "SRA  ", "OR   ", "AND  ");

    -- Number of pseudo-random vectors applied to each operation
    -- (in addition to the 6 directed vectors below)
    constant RANDOM_TESTS_PER_OP : integer := 8;

    -- Software model: compute the expected result for a given op/a/b.
    -- Written with behavioral numeric_std operators so it is independent of
    -- the ALU's structural implementation (shared adder, barrel shifter),
    -- which makes it a meaningful cross-check.
    function expected_result(op_v : std_logic_vector(3 downto 0);
                              a_v, b_v : std_logic_vector(31 downto 0))
                              return std_logic_vector is
        variable shamt : integer;  -- shift amount
    begin
        -- RV32I shifts use only the low 5 bits of operand b (range 0 to 31)
        shamt := to_integer(unsigned(b_v(4 downto 0)));
        case op_v is
            -- ADD: unsigned addition wraps modulo 2^32, matching two's complement
            when "0000" => return std_logic_vector(unsigned(a_v) + unsigned(b_v));
            -- SUB: unsigned subtraction wraps modulo 2^32
            when "1000" => return std_logic_vector(unsigned(a_v) - unsigned(b_v));
            -- SLL: logical shift left, zeros shifted in
            when "0001" => return std_logic_vector(shift_left(unsigned(a_v), shamt));
            -- SLT: result is 1 if a < b treating both as signed, else 0
            when "0010" =>
                if signed(a_v) < signed(b_v) then
                    return std_logic_vector(to_unsigned(1, 32));
                else
                    return std_logic_vector(to_unsigned(0, 32));
                end if;
            -- SLTU: result is 1 if a < b treating both as unsigned, else 0
            when "0011" =>
                if unsigned(a_v) < unsigned(b_v) then
                    return std_logic_vector(to_unsigned(1, 32));
                else
                    return std_logic_vector(to_unsigned(0, 32));
                end if;
            -- XOR: bitwise exclusive-or
            when "0100" => return a_v xor b_v;
            -- SRL: logical shift right, zeros shifted in
            when "0101" => return std_logic_vector(shift_right(unsigned(a_v), shamt));
            -- SRA: arithmetic shift right (shift_right on a signed value
            -- replicates the sign bit)
            when "1101" => return std_logic_vector(shift_right(signed(a_v), shamt));
            -- OR: bitwise or
            when "0110" => return a_v or b_v;
            -- AND: bitwise and
            when "0111" => return a_v and b_v;
            -- Any unsupported opcode: ALU is expected to output zero.
            -- (31 downto 0 => '0') gives the aggregate an explicit width,
            -- since the function's return type is unconstrained.
            when others => return (31 downto 0 => '0');
        end case;
    end function;

begin

    -- Instantiate the ALU (device under test) by direct entity instantiation
    rv32i_alu : entity work.rv32i_alu
    port map (a => a, b => b, op => op,
              result => result, zero => zero);

-- Stimulus and checking process: drives inputs, waits, then compares outputs
stim_proc: process
    variable exp_result        : std_logic_vector(31 downto 0);  -- reference-model result
    variable exp_zero          : std_logic;                      -- expected zero flag
    variable seed1, seed2      : positive := 1;                  -- RNG seeds (fixed, so runs are repeatable)
    variable rand_real         : real;                           -- uniform random value in (0, 1)
    variable rand_a, rand_b    : std_logic_vector(31 downto 0);  -- random operands

    variable pass_count        : integer;                        -- passes for the current operation
    variable total_pass        : integer := 0;                   -- passes across all operations
    variable total_tests       : integer := 0;                   -- tests run across all operations
    variable current_op_name   : string(1 to 5);                 -- name of the operation under test, used in reports

    -- Build a random 32-bit vector one bit at a time.
    -- Impure because it updates seed1/seed2 each call, so every call
    -- returns a different value.
    impure function rand_vec return std_logic_vector is
        variable v : std_logic_vector(31 downto 0);
    begin
        for i in 0 to 31 loop
            uniform(seed1, seed2, rand_real);   -- next random real in (0, 1)
            if rand_real >= 0.5 then            -- 50/50 chance for each bit
                v(i) := '1';
            else
                v(i) := '0';
            end if;
        end loop;
        return v;
    end function;

    -- Apply one pair of operands, wait for the ALU to settle, then check
    -- both the result and the zero flag against the reference model.
    -- Uses whatever opcode is currently on the 'op' signal.
    procedure run_test(a_val, b_val : std_logic_vector(31 downto 0)) is
    begin
        a <= a_val;
        b <= b_val;
        wait for 10 ns;   -- let the combinational ALU settle (also lets the new 'op' take effect)

        -- Compute what the ALU should have produced
        exp_result := expected_result(op, a_val, b_val);

        -- Expected zero flag is '1' exactly when the expected result is all zeros
        if exp_result = std_logic_vector(to_unsigned(0, 32)) then
            exp_zero := '1';
        else
            exp_zero := '0';
        end if;

        total_tests := total_tests + 1;
        -- A test passes only if both the result and the zero flag match
        if (result = exp_result) and (zero = exp_zero) then
            pass_count := pass_count + 1;
            total_pass := total_pass + 1;
        else
            -- Log the mismatch. Severity is "note" so the simulation keeps
            -- running and the remaining tests still execute.
            report "FAIL [" & current_op_name & "] a=" &
                   integer'image(to_integer(unsigned(a_val))) &
                   " b=" & integer'image(to_integer(unsigned(b_val))) &
                   " got=" & integer'image(to_integer(unsigned(result))) &
                   " exp=" & integer'image(to_integer(unsigned(exp_result)))
                   severity note;
        end if;
    end procedure;

begin
    -- Test every operation in OP_LIST, one at a time
    for op_idx in OP_LIST'range loop
        op <= OP_LIST(op_idx);                 -- select the operation
        current_op_name := OP_NAMES(op_idx);   -- set once per op
        pass_count := 0;                       -- reset the per-operation tally

        -- Directed corner-case vectors:
        run_test(x"00000000", x"00000000");   -- all zeros (checks the zero flag)
        run_test(x"00000001", x"00000001");   -- smallest nonzero operands
        run_test(x"FFFFFFFF", x"00000001");   -- all ones: overflow/wraparound, -1 as signed
        run_test(x"80000000", x"00000001");   -- most negative signed value (sign bit only)
        run_test(x"7FFFFFFF", x"00000001");   -- most positive signed value
        run_test(x"00000001", x"0000001F");   -- maximum shift amount (31)

        -- Pseudo-random vectors for broader coverage
        for i in 1 to RANDOM_TESTS_PER_OP loop
            rand_a := rand_vec;
            rand_b := rand_vec;
            run_test(rand_a, rand_b);
        end loop;

        -- Per-operation summary: passes out of (6 directed + random) tests
        report "Section " & current_op_name & ": " &
               integer'image(pass_count) & "/" &
               integer'image(6 + RANDOM_TESTS_PER_OP) & " PASS"
               severity note;
    end loop;

    -- Overall score across all operations
    report "SCORE: " & integer'image(total_pass) & " / " & integer'image(total_tests)
           severity note;

    report "Testbench complete." severity note;
    wait;   -- stop the process forever so the simulation ends
end process;

end Behavioral;