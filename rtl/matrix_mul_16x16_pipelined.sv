// Module: matrix_mul_16x16_pipelined
// 3-Stage Pipelined INT8 Matrix Multiplier for High Frequency (Fmax)

module matrix_mul_16x16_pipelined #(
    parameter int N = 16
) (
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                valid_in,

    // Flattened Input Buses (N * N * 8 bits)
    input  logic signed [(N*N*8)-1:0]           flat_a,
    input  logic signed [(N*N*8)-1:0]           flat_b,

    // Flattened Output Bus (N * N * 32 bits)
    output logic signed [(N*N*32)-1:0]          flat_c,
    output logic                                valid_out
);

  // ----------------------------------------------------------------
  // Unpacked 2D Array Signals
  // ----------------------------------------------------------------
  logic signed [7:0] mat_a [N][N];
  logic signed [7:0] mat_b [N][N];

  // Unpack Flat Input Buses
  always_comb begin
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_a[r][c] = flat_a[((r * N) + c) * 8 +: 8];
        mat_b[r][c] = flat_b[((r * N) + c) * 8 +: 8];
      end
    end
  end

  // ----------------------------------------------------------------
  // PIPELINE STAGE 1: Parallel Multipliers -> Stage 1 Registers
  // ----------------------------------------------------------------
  logic signed [15:0] mult_stage_reg [N][N][N]; // Stores [row][col][product_k]

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          for (int k = 0; k < N; k++) begin
            mult_stage_reg[r][c][k] <= 16'sd0;
          end
        end
      end
    end else if (valid_in) begin
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          for (int k = 0; k < N; k++) begin
            // Multipliers compute and immediately freeze at Stage 1 boundary
            mult_stage_reg[r][c][k] <= $signed(mat_a[r][k]) * $signed(mat_b[k][c]);
          end
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // PIPELINE STAGE 2: Partial Adder Tree -> Stage 2 Registers
  // ----------------------------------------------------------------
  // Sums the 16 products in pairs into 8 intermediate terms
  logic signed [31:0] sum_stage_reg [N][N][8];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          for (int i = 0; i < 8; i++) begin
            sum_stage_reg[r][c][i] <= 32'sd0;
          end
        end
      end
    end else begin
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          for (int i = 0; i < 8; i++) begin
            // Pairwise addition of Stage 1 products
            sum_stage_reg[r][c][i] <= $signed(mult_stage_reg[r][c][2*i]) + 
                                      $signed(mult_stage_reg[r][c][2*i + 1]);
          end
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // PIPELINE STAGE 3: Final Adder Tree -> Output Registers
  // ----------------------------------------------------------------
  logic signed [31:0] mat_c_reg [N][N];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          mat_c_reg[r][c] <= 32'sd0;
        end
      end
    end else begin
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          // Accumulate the 8 intermediate terms into the final INT32 result
          logic signed [31:0] acc;
          acc = 32'sd0;
          for (int i = 0; i < 8; i++) begin
            acc = acc + sum_stage_reg[r][c][i];
          end
          mat_c_reg[r][c] <= acc;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // CONTROL PIPELINE: 3-Stage Valid Shift Register
  // ----------------------------------------------------------------
  logic [2:0] valid_pipe;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_pipe <= 3'b000;
    end else begin
      valid_pipe <= {valid_pipe[1:0], valid_in}; // Shift valid bit down the pipe
    end
  end

  assign valid_out = valid_pipe[2];

  // Pack 2D Register Array into Flat Output Bus
  always_comb begin
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        flat_c[((r * N) + c) * 32 +: 32] = mat_c_reg[r][c];
      end
    end
  end

endmodule