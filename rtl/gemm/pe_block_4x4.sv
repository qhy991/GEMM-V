//---------------------------
// 4x4 PE Block Module
//
// Description:
// This module contains a 4x4 grid of MAC PEs (16 MACs in total).
// It implements a broadcast dataflow:
// - Input A[m] is broadcast to all PEs in row m.
// - Input B[n] is broadcast to all PEs in column n.
//
// Designed to be a reusable "building block" for the 64-MAC array.
//---------------------------

module pe_block_4x4 #(
  parameter int unsigned InDataWidth = 8,
  parameter int unsigned OutDataWidth = 32
) (
  input  logic clk_i,
  input  logic rst_ni,

  // Input Data Vectors (4 elements each)
  // Input A: 4 values (one for each row)
  input  logic signed [3:0][InDataWidth-1:0]  a_i,
  // Input B: 4 values (one for each column)
  input  logic signed [3:0][InDataWidth-1:0]  b_i,

  // Control Signals (Broadcast to all PEs)
  input  logic a_valid_i,
  input  logic b_valid_i,
  input  logic init_save_i, // Signal to save result / initialize
  input  logic acc_clr_i,   // Signal to clear accumulators

  // Output Matrix (4x4 = 16 elements)
  // Dimensions: [Row][Col]
  output logic signed [3:0][3:0][OutDataWidth-1:0] c_o
);

  // Generate variables for loops
  genvar m, n;

  generate
    // Iterate through rows (m) and columns (n)
    for (m = 0; m < 4; m++) begin : gen_rows
      for (n = 0; n < 4; n++) begin : gen_cols
        
        // Instantiate the single MAC PE
        // We reuse the provided general_mac_pe.sv
        general_mac_pe #(
          .InDataWidth  ( InDataWidth  ),
          .NumInputs    ( 1            ), // 1 pair of inputs per MAC
          .OutDataWidth ( OutDataWidth )
        ) i_mac_pe_inst (
          .clk_i        ( clk_i        ),
          .rst_ni       ( rst_ni       ),
          
          // Data Connections
          .a_i          ( a_i[m]       ), // Broadcast A[m] to this row
          .b_i          ( b_i[n]       ), // Broadcast B[n] to this col
          
          // Control Connections
          .a_valid_i    ( a_valid_i    ),
          .b_valid_i    ( b_valid_i    ),
          .init_save_i  ( init_save_i  ),
          .acc_clr_i    ( acc_clr_i    ),
          
          // Output Connection
          .c_o          ( c_o[m][n]    )
        );
        
      end
    end
  endgenerate

endmodule
