//---------------------------
// The GeMM Controller Module
//
// Description:
// This module implements the controller for the 1-MAC GeMM accelerator.
// It manages the operation by controlling the M, K, and N counters,
// which get into the address generation logic in the accelerator top.
//
// Unique to this controller is the interplay of counters and the
// main state machine. The controller uses the counters' last value
// signals to determine when to move to the next state.
//
// Parameters:
// - AddrWidth : Width of the address bus for SRAMs and counters.
//
// Ports:
// - clk_i        : Clock input.
// - rst_ni       : Active-low reset input.
// - start_i      : Start signal to initiate the GeMM operation.
// - input_valid_i: Input valid signal indicating data is ready.
// - result_valid_o: Result valid signal indicating output data is ready.
// - busy_o       : Busy signal indicating the controller is processing.
// - done_o       : Done signal indicating completion of the GeMM operation.
// - M_size_i     : Size of matrix M (number of rows in A and C).
// - K_size_i     : Size of matrix K (number of columns in A and rows in B).
// - N_size_i     : Size of matrix N (number of columns in B and C).
// - M_count_o    : Current count of M dimension.
// - K_count_o    : Current count of K dimension.
// - N_count_o    : Current count of N dimension.
//---------------------------

module gemm_controller #(
  parameter int unsigned AddrWidth = 16
)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic start_i,
  input  logic input_valid_i,
  output logic result_valid_o,
  output logic busy_o,
  output logic done_o,
  input  logic [AddrWidth-1:0] M_size_i,
  input  logic [AddrWidth-1:0] K_size_i,
  input  logic [AddrWidth-1:0] N_size_i,
  output logic [AddrWidth-1:0] M_count_o,
  output logic [AddrWidth-1:0] K_count_o,
  output logic [AddrWidth-1:0] N_count_o
);

  logic move_K_counter;
  logic move_N_counter;
  logic move_M_counter;
  logic move_counter;


  assign move_K_counter = move_counter;

  logic clear_counters;
  logic last_counter_last_value;

  typedef enum logic [1:0] {
    ControllerIdle,
    ControllerBusy,
    ControllerFinish
  } controller_state_t;

  controller_state_t current_state, next_state;

  assign busy_o = (current_state == ControllerBusy  ) ||
                  (current_state == ControllerFinish);

  
  // K Counter
  ceiling_counter #(
    .Width        (      AddrWidth ),
    .HasCeiling   (              1 )
  ) i_K_counter (
    .clk_i        ( clk_i          ),
    .rst_ni       ( rst_ni         ),
    .tick_i       ( move_K_counter ),
    .clear_i      ( clear_counters ),
    .ceiling_i    ( K_size_i       ),
    .count_o      ( K_count_o      ),
    .last_value_o ( move_N_counter )
  );

  // N Counter
  ceiling_counter #(
    .Width        (      AddrWidth ),
    .HasCeiling   (              1 )
  ) i_N_counter (
    .clk_i        ( clk_i          ),
    .rst_ni       ( rst_ni         ),
    .tick_i       ( move_N_counter ),
    .clear_i      ( clear_counters ),
    .ceiling_i    ( N_size_i   >> 2    ),
    .count_o      ( N_count_o      ),
    .last_value_o ( move_M_counter )
  );

  // M Counter
  ceiling_counter #(
    .Width        (               AddrWidth ),
    .HasCeiling   (                       1 )
  ) i_M_counter (
    .clk_i        ( clk_i                   ),
    .rst_ni       ( rst_ni                  ),
    .tick_i       ( move_M_counter          ),
    .clear_i      ( clear_counters          ),
    .ceiling_i    ( (M_size_i >> 2) == 0 ? 1 : (M_size_i >> 2) ),
    .count_o      ( M_count_o               ),
    .last_value_o ( last_counter_last_value )
  );

  // Main controller state machine
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      current_state <= ControllerIdle;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin
    next_state     = current_state;
    clear_counters = 1'b0;
    move_counter   = 1'b0;
    result_valid_o = 1'b0;
    done_o         = 1'b0;

    case (current_state)
      ControllerIdle: begin
        if (start_i) begin
          move_counter = input_valid_i;
          next_state   = ControllerBusy;
        end
      end

      ControllerBusy: begin
        move_counter = input_valid_i;
        if (last_counter_last_value && move_M_counter)  begin
          next_state = ControllerFinish;
        end else if (input_valid_i
                     && move_N_counter) begin
          result_valid_o = 1'b1;
        end
      end

      ControllerFinish: begin
        done_o         = 1'b1;
        result_valid_o = 1'b1;
        clear_counters = 1'b1;
        next_state     = ControllerIdle;
      end

      default: begin
        next_state = ControllerIdle;
      end
    endcase
  end

  //==========================================================================
  // SVA Cover Properties for FSM Coverage (Verilator --assert)
  //==========================================================================
  // synthesis translate_off
  
  // State Hit Coverage - verify each state is reached
  cover property (@(posedge clk_i) disable iff (!rst_ni)
    current_state == ControllerIdle);
  
  cover property (@(posedge clk_i) disable iff (!rst_ni)
    current_state == ControllerBusy);
  
  cover property (@(posedge clk_i) disable iff (!rst_ni)
    current_state == ControllerFinish);

  // Transition Coverage - verify state machine transitions
  // Idle -> Busy (on start)
  cover property (@(posedge clk_i) disable iff (!rst_ni)
    (current_state == ControllerIdle) && start_i |=>
    (current_state == ControllerBusy));

  // Busy -> Finish (on completion)
  cover property (@(posedge clk_i) disable iff (!rst_ni)
    (current_state == ControllerBusy) && last_counter_last_value && move_M_counter |=>
    (current_state == ControllerFinish));

  // Finish -> Idle (automatic)
  cover property (@(posedge clk_i) disable iff (!rst_ni)
    (current_state == ControllerFinish) |=>
    (current_state == ControllerIdle));

  // synthesis translate_on

endmodule
