//------------------------------------------------------------------------------
// Module: tb_one_mac_gemm
// Description: Full Testbench for CPAEP GeMM Project
//              Supports verification of Case 1, 2, and 3 with correct data packing.
//------------------------------------------------------------------------------

module tb_one_mac_gemm;
  //---------------------------
  // 1. Parameters
  //---------------------------
  parameter int unsigned InDataWidth   = 8;
  parameter int unsigned BusWidth      = 128; 
  parameter int unsigned OutDataWidth  = 32;
  parameter int unsigned C_BusWidth    = 128;

  parameter int unsigned DataDepth     = 4096;
  parameter int unsigned AddrWidth     = (DataDepth <= 1) ? 1 : $clog2(DataDepth);
  parameter int unsigned SizeAddrWidth = 8;

  parameter int unsigned NumTests = 1;

  // --- Default Test Case Configuration (Default set to Case 2) ---
  // Case 1: M=4,  K=64, N=16
  // Case 2: M=16, K=64, N=4
  // Case 3: M=32, K=32, N=32
  parameter int unsigned SingleM = 4;
  parameter int unsigned SingleK = 64;
  parameter int unsigned SingleN = 16;

  //---------------------------
  // 2. Interfaces & Signals
  //---------------------------
  logic clk_i;
  logic rst_ni;
  logic start;
  logic done;
  
  // Dynamic Size Signals
  logic [SizeAddrWidth-1:0] M_i, K_i, N_i;

  // SRAM Signals
  logic [AddrWidth-1:0] sram_a_addr;
  logic [AddrWidth-1:0] sram_b_addr;
  logic [AddrWidth-1:0] sram_c_addr;

  logic signed [BusWidth-1:0]   sram_a_rdata;
  logic signed [BusWidth-1:0]   sram_b_rdata;
  logic signed [C_BusWidth-1:0] sram_c_wdata;
  logic                         sram_c_we;

  // Cycle Counting
  int unsigned start_cycle;
  int unsigned end_cycle;
  int unsigned duration;

  //---------------------------
  // 3. Memory Models (Shadow & Real)
  //---------------------------
  // Shadow memories are used for Golden Model calculation and Verification
  logic signed [OutDataWidth-1:0] G_memory     [DataDepth]; // Golden Result
  logic signed [InDataWidth-1:0]  shadow_a_mem [DataDepth]; // Flat copy of A
  logic signed [InDataWidth-1:0]  shadow_b_mem [DataDepth]; // Flat copy of B
  logic signed [OutDataWidth-1:0] shadow_c_mem [DataDepth]; // Reconstructed C from DUT

  // Real SRAM Instances
  single_port_memory #(.DataWidth(BusWidth), .DataDepth(DataDepth), .AddrWidth(AddrWidth)) i_sram_a (
    .clk_i(clk_i), .rst_ni(rst_ni), .mem_addr_i(sram_a_addr), .mem_we_i('0), .mem_wr_data_i('0), .mem_rd_data_o(sram_a_rdata)
  );

  single_port_memory #(.DataWidth(BusWidth), .DataDepth(DataDepth), .AddrWidth(AddrWidth)) i_sram_b (
    .clk_i(clk_i), .rst_ni(rst_ni), .mem_addr_i(sram_b_addr), .mem_we_i('0), .mem_wr_data_i('0), .mem_rd_data_o(sram_b_rdata)
  );

  single_port_memory #(.DataWidth(C_BusWidth), .DataDepth(DataDepth), .AddrWidth(AddrWidth)) i_sram_c (
    .clk_i(clk_i), .rst_ni(rst_ni), .mem_addr_i(sram_c_addr), .mem_we_i(sram_c_we), .mem_wr_data_i(sram_c_wdata), .mem_rd_data_o()
  );

  //---------------------------
  // 4. DUT Instantiation
  //---------------------------
  gemm_accelerator_top #(
    .InDataWidth   ( InDataWidth   ),
    .OutDataWidth  ( OutDataWidth  ),
    .AddrWidth     ( AddrWidth     ),
    .SizeAddrWidth ( SizeAddrWidth ),
    .BusWidth      ( BusWidth      )
  ) i_dut (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .start_i        ( start          ),
    .N_size_i       ( N_i            ),
    .M_size_i       ( M_i            ),
    .K_size_i       ( K_i            ),
    .sram_a_addr_o  ( sram_a_addr    ),
    .sram_b_addr_o  ( sram_b_addr    ),
    .sram_c_addr_o  ( sram_c_addr    ),
    .sram_a_rdata_i ( sram_a_rdata   ),
    .sram_b_rdata_i ( sram_b_rdata   ),
    .sram_c_wdata_o ( sram_c_wdata   ),
    .sram_c_we_o    ( sram_c_we      ),
    .done_o         ( done           )
  );

  //---------------------------
  // 5. Includes (Tasks & Functions)
  //---------------------------
  // Assuming these files exist in your folder structure as per instructions
  `include "includes/common_tasks.svh"
  `include "includes/test_tasks.svh"
  `include "includes/test_func.svh"

  //---------------------------
  // 6. Clock Generation
  //---------------------------
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i; 
  end

  //---------------------------
  // 7. Main Test Sequence
  //---------------------------
  initial begin
    // --- Variable Declarations ---
    logic [InDataWidth-1:0] val;
    logic [BusWidth-1:0]    packed_val;
    
    // Loop iterators
    int m, k, n, sub_m, sub_n;
    int m_loops, n_loops;
    
    // Unpacking variables
    int cols_chunk_count;
    int stride;
    int addr;
    int final_col;
    logic [C_BusWidth-1:0] huge_word;
    logic [OutDataWidth-1:0] val32;
    
    // Configuration
    int PACK_FACTOR;
    
    // --- Setup ---
    PACK_FACTOR = BusWidth / InDataWidth; // 128 / 8 = 16
    
    // Reset Sequence
    start  = 1'b0;
    rst_ni = 1'b0;
    #50;
    rst_ni = 1'b1;
    #20;

    // --- Test Loop ---
    for (int num_test = 0; num_test < NumTests; num_test++) begin
      $display("\n========================================");
      $display("Starting Test %0d", num_test);
      
      // Set Matrix Dimensions
      M_i = SingleM;
      K_i = SingleK;
      N_i = SingleN;
      
      $display("Dimensions -> M: %0d, K: %0d, N: %0d", M_i, K_i, N_i);

      // -------------------------------------------------------------------
      // Step A: Initialize Memories (Packing Logic)
      // -------------------------------------------------------------------
      // Critical Logic for Case 2 (M=16):
      // m_loops will be 1. The code packs rows 0-15 (sub_m) of Matrix A 
      // into a single 128-bit SRAM word.
      // This aligns with the RTL optimization which reads all 16 rows at once.
      
      m_loops = (M_i < PACK_FACTOR) ? 1 : (M_i / PACK_FACTOR);
      n_loops = (N_i < PACK_FACTOR) ? 1 : (N_i / PACK_FACTOR);

      // --- Initialize SRAM A ---
      for (m = 0; m < m_loops; m++) begin
        for (k = 0; k < K_i; k++) begin
          packed_val = '0;
          for (sub_m = 0; sub_m < PACK_FACTOR; sub_m++) begin
            val = $urandom(); 
            // Construct BusWidth (128-bit) data
            packed_val[sub_m*InDataWidth +: InDataWidth] = val;
            
            // Fill Shadow Memory (Used for Golden Model calculation)
            // Note: Shadow Memory uses flat addressing for software simplicity
            if ((m*PACK_FACTOR+sub_m) < M_i) begin
               shadow_a_mem[(m*PACK_FACTOR+sub_m)*K_i + k] = val;
            end
          end
          i_sram_a.memory[m*K_i + k] = packed_val;
        end
      end

      // --- Initialize SRAM B ---
      for (k = 0; k < K_i; k++) begin
        for (n = 0; n < n_loops; n++) begin
          packed_val = '0;
          for (sub_n = 0; sub_n < PACK_FACTOR; sub_n++) begin
            val = $urandom();
            packed_val[sub_n*InDataWidth +: InDataWidth] = val;
            
            if ((n*PACK_FACTOR + sub_n) < N_i) begin
                shadow_b_mem[k * N_i + (n*PACK_FACTOR+sub_n)] = val;
            end
          end
          // SRAM B Layout
          i_sram_b.memory[k*(n_loops)+n] = packed_val;
        end
      end

      // -------------------------------------------------------------------
      // Step B: Calculate Golden Result (Software Reference)
      // -------------------------------------------------------------------
      // Call function from includes/test_func.svh
      gemm_golden(M_i, K_i, N_i, shadow_a_mem, shadow_b_mem, G_memory);

      clk_delay(1);

      // -------------------------------------------------------------------
      // Step C: Run Hardware & Measure Performance
      // -------------------------------------------------------------------
      $display("Starting Hardware Execution...");
      start_cycle = $time / 10; // Assuming 10ns period (since #5 toggle)
      
      // Start Signal
      @(posedge clk_i);
      start <= 1'b1;
      @(posedge clk_i);
      start <= 1'b0;

      // Wait for Done
      wait(done == 1'b1);
      end_cycle = $time / 10;
      duration = end_cycle - start_cycle - 1; // -1 for calibration

      $display("Hardware Execution Finished.");
      $display("----------------------------------------");
      $display("Cycles Taken: %0d", duration);
      $display("----------------------------------------");

      // -------------------------------------------------------------------
      // Step D: Unpack Result from SRAM C for Verification
      // -------------------------------------------------------------------
      // The Unpacking logic here adapts to the RTL writing method.
      // For Case 2 (M=16, N=4):
      // Stride = 1.
      // Each row of SRAM C stores 4 int32s (128-bit).
      // This exactly corresponds to one row of Case 2 (4 columns).
      
      cols_chunk_count = (N_i < 4) ? 1 : (N_i >> 2);
      stride           = (N_i < 4) ? 1 : (N_i >> 2);

      for (int r = 0; r < M_i; r++) begin
          for (int c_chunk = 0; c_chunk < cols_chunk_count; c_chunk++) begin
             
             // Calculate read address
             addr = r * stride + c_chunk;
             huge_word = i_sram_c.memory[addr]; 
             
             // Unpack 128-bit into 4x 32-bit
             for (int i = 0; i < 4; i++) begin
                val32 = huge_word[i*32 +: 32];
                final_col = c_chunk * 4 + i;
                
                // Store into Shadow Memory for comparison
                if (final_col < N_i) begin
                    shadow_c_mem[r * N_i + final_col] = val32;
                end
             end
          end
      end

      // -------------------------------------------------------------------
      // Step E: Verify against Golden Model
      // -------------------------------------------------------------------
      // 0 = Continue on error, 1 = Stop on error
      verify_result_c(G_memory, shadow_c_mem, DataDepth, 0);

      clk_delay(10);
    end

    $display("\n========================================");
    $display("All Simulations Completed.");
    $finish;
  end

endmodule
