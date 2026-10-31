# 16x16 Pipelined Matrix Multiplier

A parameterized SystemVerilog design that multiplies two signed 16x16 matrices
of 8-bit integers. Each output element is a signed 32-bit dot product. The
design uses a three-stage pipeline and includes a self-checking testbench.

## Project layout

```text
MAC_16/
├── rtl/
│   └── matrix_mul_16x16_pipelined.sv
├── tb/
│   └── tb_matrix_mul_16x16_pipelined.sv
├── .gitignore
└── README.md
```

## Design overview

The top-level module is `matrix_mul_16x16_pipelined`, declared in
`rtl/matrix_mul_16x16_pipelined.sv`. Its `N` parameter defaults to 16.

For each output element, the design computes the matrix product:

```text
C[r][c] = sum(A[r][k] * B[k][c]), for k = 0 to N-1
```

The implementation has three registered stages:

1. **Products:** Calculate and register all `N` signed 8-bit products for each
   output element. Products are stored as signed 16-bit values.
2. **Partial sums:** Add adjacent products in pairs, producing eight signed
   32-bit partial sums per output element when `N` is 16.
3. **Final sums:** Add the partial sums and register the signed 32-bit matrix
   result.

The active-low asynchronous reset, `rst_n`, clears the pipeline registers and
the valid-bit pipeline. The `valid_in` signal marks an input matrix as valid.
`valid_out` is delayed by three clock cycles to indicate when the corresponding
result is available. The pipeline can accept a new matrix every cycle, including
back-to-back inputs.

### Top-level interface

| Port | Direction | Width for `N=16` | Description |
|---|---|---:|---|
| `clk` | Input | 1 | Clock; pipeline stages update on its rising edge |
| `rst_n` | Input | 1 | Active-low asynchronous reset |
| `valid_in` | Input | 1 | Marks an input matrix pair as valid |
| `flat_a` | Input | 2048 | Flattened signed 8-bit matrix A |
| `flat_b` | Input | 2048 | Flattened signed 8-bit matrix B |
| `flat_c` | Output | 8192 | Flattened signed 32-bit result matrix C |
| `valid_out` | Output | 1 | Indicates a valid result after pipeline latency |

### Flattened matrix ordering

Both input matrices and the output matrix are row-major. The element at row
`r`, column `c` begins at bit offset `(r * N + c) * element_width`. Thus,
`flat_a[(r*N+c)*8 +: 8]` holds `A[r][c]`, and
`flat_c[(r*N+c)*32 +: 32]` holds `C[r][c]`. Input and output elements are
signed two's-complement values.

## Running the testbench

The testbench uses Icarus Verilog and `vvp`. From the project root, compile and
run it with:

```sh
iverilog -g2012 -s tb_matrix_mul_16x16_pipelined \
  -o /tmp/mac16_tb_sim \
  rtl/matrix_mul_16x16_pipelined.sv \
  tb/tb_matrix_mul_16x16_pipelined.sv
vvp /tmp/mac16_tb_sim
```

The testbench compares every result element against a software reference model.
It covers:

- A variable ramp pattern.
- Signed positive and negative values.
- Two different matrices sent on consecutive cycles to check pipeline
  throughput and data alignment.

The expected successful run ends with:

```text
SUCCESS: All 4 tests passed cleanly with 0 errors!
```

## Requirements

- Icarus Verilog with SystemVerilog (`-g2012`) support.
- `vvp` runtime (typically installed with Icarus Verilog).
