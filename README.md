# 16x16 INT8 Pipelined Matrix Multiplication Accelerator

An industrial-grade, 3-stage pipelined 16x16 INT8 matrix multiplication execution engine designed in SystemVerilog. Built to demonstrate high-throughput spatial parallelism, critical path optimization, and cycle-accurate pipeline control required for modern Deep Learning Accelerators (TPUs/NPUs).

---

## Architecture Overview

In a single-cycle $16 \times 16$ matrix engine, performing $4,096$ INT8 multiplications and a 16-element sum tree in a single clock cycle creates a long combinational critical path delay. This severely caps the maximum clock frequency ($F_{max}$).

This design implements a **3-stage pipelined data path** that slices the compute graph into three balanced operational stages using flip-flop walls. This reduces propagation delay per cycle, allowing the engine to run at significantly higher clock frequencies while delivering a new $16 \times 16$ matrix result every single clock cycle once the pipeline is full.

```text
+-----------------------------------------------------------------------------------+
|                               PIPELINED COMPUTE CORE                              |
|                                                                                   |
|  [ flat_a, flat_b ]                                                               |
|          │                                                                        |
|          ▼                                                                        |
|  ┌───────────────┐                                                                |
|  │ STAGE 1 LOGIC │ ──► 4,096 INT8 Parallel Multipliers                            |
|  └───────┬───────┘                                                                |
|          ▼                                                                        |
|  ================= PIPELINE REGISTER 1 (mult_stage_reg) ========================  |
|          │                                                                        |
|          ▼                                                                        |
|  ┌───────────────┐                                                                |
|  │ STAGE 2 LOGIC │ ──► Pairwise Adder Tree (16 products -> 8 partial sums)        |
|  └───────┬───────┘                                                                |
|          ▼                                                                        |
|  ================= PIPELINE REGISTER 2 (sum_stage_reg) =========================  |
|          │                                                                        |
|          ▼                                                                        |
|  ┌───────────────┐                                                                |
|  │ STAGE 3 LOGIC │ ──► Final Accumulator (8 partial sums -> 1 INT32 output)       |
|  └───────┬───────┘                                                                |
|          ▼                                                                        |
|  ================= PIPELINE REGISTER 3 (mat_c_reg) =============================  |
|          │                                                                        |
|          ▼                                                                        |
|  [ flat_c, valid_out ]                                                            |
+-----------------------------------------------------------------------------------+
```

---

## Technical Specifications & Features

- **Arithmetic Precision:** Signed INT8 Inputs (`flat_a`, `flat_b`), Signed INT32 Outputs (`flat_c`).
- **Parallel Compute Units:** 4,096 INT8 Multipliers operating simultaneously.
- **Pipeline Depth:** 3 Clock Cycles (Latency = 3 cycles, Throughput = 1 matrix per cycle).
- **Control Synchronization:** 3-bit Shift Register (`valid_pipe`) tracking dataset progression down the pipeline to assert `valid_out` precisely on data completion.
- **Bus Widths:**
  - `flat_a`, `flat_b`: $16 \times 16 \times 8 \text{ bits} = \mathbf{2,048\text{ bits}}$
  - `flat_c`: $16 \times 16 \times 32 \text{ bits} = \mathbf{8,192\text{ bits}}$

---

## Repository Structure

```text
16x16-int8-matrix-multiplier/
├── rtl/
│   └── matrix_mul_16x16_pipelined.sv   # 3-Stage Pipelined SystemVerilog Core
├── tb/
│   └── tb_matrix_mul_16x16_pipelined.sv # Automated Self-Checking Testbench
├── docs/
│   └── wave_verification.png          # GTKWave Timing Diagram Screenshot
├── sim/                                # Simulation build directory (git-ignored)
│   ├── pipe16_sim                      # Compiled binary
│   └── dump.vcd                        # VCD Waveform file
├── .gitignore                          # Git Ignore rules for sim artifacts
├── LICENSE                             # MIT License
└── README.md                           # Documentation
```

---

## Pipeline Stage Breakdown

### Stage 1: Parallel Multiplication
Unpacks flattened input buses into 2D matrices ($A$ and $B$) and computes 4,096 independent products ($A_{i,k} \times B_{k,j}$) concurrently. Results are latched into `mult_stage_reg`.

### Stage 2: Pairwise Reduction
Reads the 16 multiplication products per dot product from `mult_stage_reg` and sums adjacent elements in pairs ($16 \rightarrow 8$ intermediate sums). This reduces the adder tree depth for the next cycle and latches outputs into `sum_stage_reg`.

### Stage 3: Accumulation & Output
Sums the 8 intermediate values from `sum_stage_reg` into the final 32-bit INT32 output element ($8 \rightarrow 1$). Latches the complete matrix into `mat_c_reg` and packs it onto the 8,192-bit `flat_c` output bus.

### Control Pipeline (`valid_pipe`)
To ensure handshaking integrity, a 3-bit shift register tracks the `valid_in` pulse:

$$\text{valid\_pipe} \Leftarrow \{\text{valid\_pipe}[1:0], \text{valid\_in}\}$$

`valid_out` is driven by `valid_pipe[2]`, guaranteeing that downstream logic only reads `flat_c` when valid computation results have reached Stage 3.

---

## Verification & Simulation

Verification is handled by an automated SystemVerilog testbench (`tb_matrix_mul_16x16_pipelined.sv`) paired with Icarus Verilog and GTKWave.

### Testbench Features
1. **Golden Software Reference Model:** Dynamically computes expected outputs in a behavioral reference block for every input set.
2. **256-Element Automated Comparison:** Iterates through every row and column ($16 \times 16 = 256$ elements) comparing hardware output to expected software values.
3. **Corner Cases Covered:**
   - Sequential ramp matrices ($r+c, r-c$)
   - Signed negative numbers and bound limits
   - Back-to-back streaming stress test (verifying pipeline stall safety)

### Running the Simulation

#### Prerequisites
Install Icarus Verilog and GTKWave (Linux / WSL / macOS):
```bash
sudo apt update
sudo apt install iverilog gtkwave -y
```

#### Execute Testbench
Compile and run the simulation using IEEE 1800-2012 SystemVerilog support:
```bash
# Compile and run simulation
iverilog -g2012 -o pipe16_sim rtl/matrix_mul_16x16_pipelined.sv tb/tb_matrix_mul_16x16_pipelined.sv && vvp pipe16_sim
```

#### View Waveforms
To inspect clock-edge timing and pipeline latency:
```bash
gtkwave dump.vcd &
```

---

## Mathematical Verification Example

For input matrices generated as $A_{r,c} = r + c$ and $B_{r,c} = r - c$, element $C[0][0]$ computes as:

$$C[0][0] = \sum_{k=0}^{15} A[0][k] \times B[k][0] = \sum_{k=0}^{15} (0 + k) \times (k - 0) = \sum_{k=0}^{15} k^2$$

$$C[0][0] = 0^2 + 1^2 + 2^2 + \dots + 15^2 = \frac{15 \times 16 \times 31}{6} = \mathbf{1240}$$

The simulation cleanly asserts `PASS` for all 256 matrix outputs, verifying zero bit-truncation or sign-extension defects.

---

## Future Extensions (Phase 2 & 3 Roadmap)

- [ ] **AXI4-Stream Interface:** Wrap the engine with `tvalid`, `tready`, and `tlast` protocol handshaking to manage backpressure.
- [ ] **Ping-Pong SRAM Buffers:** Implement dual-bank SRAM memory to allow the CPU to load Matrix $N+1$ while the engine processes Matrix $N$.
- [ ] **FPGA Synthesis:** Synthesize in Xilinx Vivado to report LUT/DSP utilization and exact $F_{max}$ numbers.

---

## Author

- **Raviteja P.** - *Electronics and Communication Engineering*
- **GitHub:** [@zcode-r](https://github.com/zcode-r)