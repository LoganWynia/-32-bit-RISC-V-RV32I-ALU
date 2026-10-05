# RV32I ALU (VHDL)

A 32-bit ALU implementing the RV32I integer register-register operations,
designed to minimize hardware by sharing datapath resources.

## Design highlights

- **One adder for four operations.** ADD, SUB, SLT, and SLTU all use a single
  34-bit add. Subtraction inverts `b` and injects the +1 as a carry-in by
  appending a bit to both operands. SLTU is the inverted carry-out; SLT is the
  sign bit of the difference, corrected for the case where operand signs differ
  (where overflow would otherwise give the wrong answer).
- **One barrel shifter for three operations.** SLL, SRL, and SRA share a
  5-stage logarithmic right shifter. Left shifts reverse the input bits, shift
  right, and reverse the result, so no separate left-shift hardware is needed.
  SRA differs from SRL only in the fill bit.
- **Opcode = instruction fields.** `op(3)` is `funct7[5]` and `op(2:0)` is
  `funct3`, so the decoder can feed the ALU directly from the instruction.
- **Zero flag** on every result, usable for BEQ/BNE via SUB.

## Operations

| op     | Operation | Result                          |
|--------|-----------|---------------------------------|
| `0000` | ADD       | a + b                           |
| `1000` | SUB       | a − b                           |
| `0001` | SLL       | a << b[4:0]                     |
| `0010` | SLT       | signed(a) < signed(b)           |
| `0011` | SLTU      | unsigned(a) < unsigned(b)       |
| `0100` | XOR       | a xor b                         |
| `0101` | SRL       | a >> b[4:0] (logical)           |
| `1101` | SRA       | a >> b[4:0] (arithmetic)        |
| `0110` | OR        | a or b                          |
| `0111` | AND       | a and b                         |

## Interface

| Port     | Dir | Width | Description                  |
|----------|-----|-------|------------------------------|
| `a`, `b` | in  | 32    | Operands                     |
| `op`     | in  | 4     | Operation select (see above) |
| `result` | out | 32    | Result                       |
| `zero`   | out | 1     | High when `result` is zero   |

## Simulation

```sh
ghdl -a --std=08 src/rv32i_alu.vhd tb/rv32i_alu_tb.vhd
ghdl -r --std=08 alu32_tb
```

## Verification



## Repository layout

```
src/   rv32i_alu.vhd
tb/    rv32i_alu_tb.vhd
```

## License

MIT
