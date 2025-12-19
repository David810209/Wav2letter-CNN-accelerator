// Copyright 2021 The CFU-Playground Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
`include "global_buffer_bram.v"
`include "VPU.v"

module Cfu (
  input               cmd_valid,
  output              cmd_ready,
  input      [9:0]    cmd_payload_function_id,
  input      [31:0]   cmd_payload_inputs_0,
  input      [31:0]   cmd_payload_inputs_1,
  output              rsp_valid,
  input               rsp_ready,
  output reg [31:0]   rsp_payload_outputs_0,
  input               reset,
  input               clk
);

reg            in_valid;
reg [12:0]      K;
reg [7:0]      M;
reg [7:0]      N;
reg signed [31:0] input_offset;
reg [17:0]     K_x_M;
// wire [15:0]     M_x_N;
// wire [15:0]     K_x_N;
reg [15:0]     A_size;
reg [15:0]     B_size;
reg [15:0]     C_size;
wire            busy;
wire            A_wr_en;
wire [15:0]     A_index;
reg [15:0]      A_index_reg;
wire [31:0]     A_data_in;
wire [31:0]     A_data_out;
wire [15:0]     A_index_TPU;

wire            B_wr_en;
wire [15:0]     B_index;
reg [15:0]      B_index_reg;
wire [15:0]     B_index_TPU;
wire [31:0]     B_data_in;
wire [31:0]     B_data_out;
wire            C_wr_en;
wire [15:0]     C_index;
wire [15:0]     C_index_TPU;
reg  [15:0]     C_index_reg;
wire [127:0]    C_data_in;
wire [127:0]    C_data_out;
reg             rsp_valid_reg;

wire [6:0] func = cmd_payload_function_id[9:3];
reg [2:0] state, next_state;
localparam IDLE = 0, INPUT_A = 1,INPUT_B = 2,COMPUTE = 3, OUTPUT_C = 4, DELAY = 5, OFFSET = 6;

always @(posedge clk or posedge reset)begin
  if(reset) begin
    K_x_M <= 0;
    A_size <= 0;
    B_size <= 0;
    C_size <= 0;
  end
  else begin
    K_x_M <= M * K;
    A_size <= K_x_M >> 2;
    B_size <= K >> 2;
    C_size <= M >> 2;
  end
end
always @(posedge clk or posedge reset) begin
  if (reset) begin
    M <= 0;
    N <= 0;
    K <= 0;
    input_offset <= 0;
  end else if(cmd_valid && func== 3) begin
    M <= cmd_payload_inputs_0;
    K <= cmd_payload_inputs_1;
    N <= N;
    input_offset <= input_offset;
  end 
  else if(cmd_valid && func== 4) begin
    M <= M;
    K <= K;
    N <= cmd_payload_inputs_0;
    input_offset <= cmd_payload_inputs_1;
  end
  else begin
    M <= M;
    N <= N;
    K <= K;
    input_offset <= input_offset;
  end
end

always @(posedge clk or posedge reset) begin
  if (reset) begin
    state <= IDLE;
  end else begin
    state <= next_state;
  end
end

always @(*) begin
  case (state)
  IDLE: begin
    if(cmd_valid)begin
      if(func== 0) begin
        next_state = INPUT_A;
      end
      else if(func== 1) begin
        next_state = INPUT_B;
      end
      else if(func == 3 || func == 4) begin
        next_state = OFFSET;
      end
      else begin
        next_state = IDLE;
      end
    end
    else begin
      next_state = IDLE;
    end
  end
  INPUT_A: next_state = (A_index_reg >= A_size) ? IDLE : INPUT_A;
  INPUT_B: next_state = (B_index_reg >= B_size) ? COMPUTE : INPUT_B;
  COMPUTE: next_state = (~in_valid && ~busy) ? OUTPUT_C : COMPUTE;
  OUTPUT_C: next_state = (C_index_reg >= C_size) ? DELAY : OUTPUT_C;
  DELAY: next_state = IDLE;
  OFFSET: next_state = IDLE;
  default: next_state = IDLE;
  endcase
end

assign rsp_valid = (state == INPUT_A || state == INPUT_B || rsp_valid_reg == 1 || state == OFFSET);
assign cmd_ready = state != COMPUTE;

always @(posedge clk or posedge reset) begin
  if (reset) begin
    A_index_reg <= 0;
  end else if(next_state == INPUT_A && A_index_reg < A_size) begin
    if(cmd_valid && func == 0) begin
      A_index_reg <= A_index_reg + 1;
    end else begin
      A_index_reg <= A_index_reg;
    end
  end else begin
    A_index_reg <= 0;
  end
end
assign A_wr_en = A_index_reg < A_size && cmd_valid && func == 0;
assign A_data_in = cmd_payload_inputs_0;
always @(posedge clk or posedge reset) begin
  if (reset) begin
    B_index_reg <= 0;
  end else if(next_state == INPUT_B && B_index_reg < B_size) begin
    if(cmd_valid && func == 1) begin
      B_index_reg <= B_index_reg + 1;
    end else begin
      B_index_reg <= B_index_reg;
    end
  end else begin
    B_index_reg <= 0;
  end
end
assign B_wr_en = B_index_reg < B_size && cmd_valid && func== 1;
assign B_data_in = cmd_payload_inputs_0;

reg [1:0] out_cnt;
always @(posedge clk or posedge reset) begin
  if (reset) begin
    C_index_reg <= 0;
    rsp_payload_outputs_0 <= 0;
    out_cnt <= 0;
    rsp_valid_reg <= 0;
  end else if(state == OUTPUT_C && C_index_reg < C_size) begin
    if(cmd_valid) begin
      case(out_cnt)
        0: rsp_payload_outputs_0 <= C_data_out[127:96];
        1: rsp_payload_outputs_0 <= C_data_out[95:64];
        2: rsp_payload_outputs_0 <= C_data_out[63:32];
        3: rsp_payload_outputs_0 <= C_data_out[31:0];
        default: rsp_payload_outputs_0 <= 0;
      endcase
      rsp_valid_reg <= 1;
      out_cnt <= out_cnt + 1;
      if(out_cnt == 3) begin
      C_index_reg <= C_index_reg + 1;
      end 
      else begin
        C_index_reg <= C_index_reg;
      end

    end else begin
      C_index_reg <= C_index_reg;
      rsp_valid_reg <= 0;
      out_cnt <= out_cnt;
    end
  end else begin
    C_index_reg <= 0;
    rsp_payload_outputs_0 <= 0;
    out_cnt <= 0;
    rsp_valid_reg <= 0;
  end
end

always @(posedge clk or posedge reset) begin
  if (reset) begin
    in_valid <= 0;
  end else if(state == INPUT_B && next_state == COMPUTE) begin
    in_valid <= 1;
  end else begin
    in_valid <= 0;
  end
end

assign A_index = A_wr_en ? A_index_reg : A_index_TPU;
assign B_index = B_wr_en ? B_index_reg : B_index_TPU;
assign C_index = C_wr_en ? C_index_TPU : C_index_reg;

global_buffer_bram #(
    .ADDR_BITS(16),
    .DATA_BITS(32)
)
gbuff_A(
    .clk(clk),
    .rst_n(~reset),
    .ram_en(1'b1),
    .wr_en(A_wr_en),
    .index(A_index),
    .data_in(A_data_in),
    .data_out(A_data_out)
);

global_buffer_bram #(
    .ADDR_BITS(11),
    .DATA_BITS(32)
) gbuff_B(
    .clk(clk),
    .rst_n(~reset),
    .ram_en(1'b1),
    .wr_en(B_wr_en),
    .index(B_index),
    .data_in(B_data_in),
    .data_out(B_data_out)
);

global_buffer_bram #(
    .ADDR_BITS(10),
    .DATA_BITS(128)
) gbuff_C(
    .clk(clk),
    .rst_n(~reset),
    .ram_en(1'b1),
    .wr_en(C_wr_en),
    .index(C_index),
    .data_in(C_data_in),
    .data_out(C_data_out)
);

VPU My_VPU(
    .clk            (clk),     
    .rst_n          (~reset),     
    .in_valid       (in_valid),         
    .K              (K), 
    .M              (M), 
    .N              (N), 
    .busy           (busy),     
    .A_wr_en        (),         
    .A_index        (A_index_TPU),         
    .A_data_in      (),         
    .A_data_out     (A_data_out),         
    .B_wr_en        (),         
    .B_index        (B_index_TPU),         
    .B_data_in      (),         
    .B_data_out     (B_data_out),         
    .C_wr_en        (C_wr_en),         
    .C_index        (C_index_TPU),         
    .C_data_in      (C_data_in),         
    .C_data_out     ()         ,
    .input_offset   (input_offset)     
);

endmodule
