`timescale 1ns/1ps

module tb_matrix_mul_16x16_pipelined;

  localparam int N = 16;

  logic                                clk;
  logic                                rst_n;
  logic                                valid_in;
  logic signed [(N*N*8)-1:0]           flat_a;
  logic signed [(N*N*8)-1:0]           flat_b;
  logic signed [(N*N*32)-1:0]          flat_c;
  logic                                valid_out;

  // Unpacked local arrays for test stimulus and verification
  logic signed [7:0]  mat_a [N][N];
  logic signed [7:0]  mat_b [N][N];
  logic signed [31:0] mat_c_hardware [N][N];
  logic signed [31:0] mat_c_expected [N][N];

  int error_count = 0;
  int test_pass_count = 0;
  int cycle_count = 0;

  // Instantiate Design Under Test (DUT)
  matrix_mul_16x16_pipelined #(.N(N)) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),
      .flat_a   (flat_a),
      .flat_b   (flat_b),
      .flat_c   (flat_c),
      .valid_out(valid_out)
  );

  // Clock Generation (100 MHz -> 10ns Period)
  always #5 clk = ~clk;

  // Global Cycle Counter
  always_ff @(posedge clk) begin
    if (rst_n) cycle_count++;
  end

  // Pack 2D Stimulus into 1D Flat Buses
  always_comb begin
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        flat_a[((r * N) + c) * 8 +: 8] = mat_a[r][c];
        flat_b[((r * N) + c) * 8 +: 8] = mat_b[r][c];
      end
    end
  end

  // Unpack 1D Hardware Output Bus into 2D Array
  always_comb begin
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_c_hardware[r][c] = flat_c[((r * N) + c) * 32 +: 32];
      end
    end
  end

  // Golden Reference Software Model (Computes Expected 16x16 Output)
  task compute_golden_reference();
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        logic signed [31:0] sum;
        sum = 32'sd0;
        for (int k = 0; k < N; k++) begin
          sum = sum + ($signed(mat_a[r][k]) * $signed(mat_b[k][c]));
        end
        mat_c_expected[r][c] = sum;
      end
    end
  endtask

  // Automated Output Comparison Task
  task verify_outputs(input string test_name);
    int test_errors;
    test_errors = 0;
    
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        if (mat_c_hardware[r][c] !== mat_c_expected[r][c]) begin
          $display("[ERROR] %s Mismatch at C[%0d][%0d]! HW = %0d, Expected = %0d", 
                    test_name, r, c, mat_c_hardware[r][c], mat_c_expected[r][c]);
          test_errors++;
          error_count++;
        end
      end
    end

    if (test_errors == 0) begin
      $display("[PASS] %s: All 256 elements of 16x16 matrix matched perfectly!", test_name);
      test_pass_count++;
    end else begin
      $display("[FAIL] %s: Total mismatches = %0d", test_name, test_errors);
    end
  endtask

  // Main Test Sequence
  initial begin

    $dumpfile("dump.vcd"); // Creates the waveform database file
    $dumpvars(0, tb_matrix_mul_16x16_pipelined); // Dumps all signals in the module

    clk      = 0;
    rst_n    = 0;
    valid_in = 0;

    $display("========== STARTING PIPELINED 16x16 MATRIX MULTIPLIER TESTBENCH ==========");

    // Hold Reset
    #15;
    rst_n = 1;
    #10;

    // ----------------------------------------------------------------
    // TEST 1: Variable Pattern (r+c, r-c)
    // ----------------------------------------------------------------
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_a[r][c] = $signed(r + c);
        mat_b[r][c] = $signed(r - c);
      end
    end
    compute_golden_reference();

    @(negedge clk);
    valid_in = 1'b1;
    @(negedge clk);
    valid_in = 1'b0;

    // Wait for 3-cycle pipeline latency
    while (!valid_out) @(negedge clk);
    verify_outputs("Test 1 (Ramp Pattern)");

    // ----------------------------------------------------------------
    // TEST 2: Signed Negative Numbers & Extreme Bounds
    // ----------------------------------------------------------------
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_a[r][c] = (r % 2 == 0) ? -8'sd10 : 8'sd15;
        mat_b[r][c] = (c % 2 == 0) ? 8'sd20  : -8'sd5;
      end
    end
    compute_golden_reference();

    @(negedge clk);
    valid_in = 1'b1;
    @(negedge clk);
    valid_in = 1'b0;

    while (!valid_out) @(negedge clk);
    verify_outputs("Test 2 (Signed & Negative Pattern)");

    // ----------------------------------------------------------------
    // TEST 3: Back-to-Back Pipeline Stress Test (2 Consecutive Matrices)
    // ----------------------------------------------------------------
    // Load Matrix 3
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_a[r][c] = 8'sd2;
        mat_b[r][c] = 8'sd3;
      end
    end
    compute_golden_reference();

    @(negedge clk);
    valid_in = 1'b1;

    @(negedge clk);
    // Send new inputs immediately on next cycle without resetting valid_in
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_a[r][c] = 8'sd4;
        mat_b[r][c] = 8'sd5;
      end
    end

    @(negedge clk);
    valid_in = 1'b0;

    // Catch Matrix 3 output
    while (!valid_out) @(negedge clk);
    verify_outputs("Test 3 (Pipelined Stream - Matrix 3)");

    // Catch Matrix 4 output on immediate next cycle
    @(negedge clk);
    // Recompute reference for Matrix 4 values (all 4s and 5s)
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        mat_a[r][c] = 8'sd4;
        mat_b[r][c] = 8'sd5;
      end
    end
    compute_golden_reference();
    verify_outputs("Test 4 (Pipelined Stream - Matrix 4)");

    // ----------------------------------------------------------------
    // Final Verification Summary
    // ----------------------------------------------------------------
    $display("==================================================");
    if (error_count == 0) begin
      $display("SUCCESS: All %0d tests passed cleanly with 0 errors!", test_pass_count);
    end else begin
      $display("FAILURE: Total verification errors = %0d", error_count);
    end
    $display("==================================================");
    $finish;
  end

endmodule