module VPU(
    clk,
    rst_n,

    in_valid,
    K,
    M,
    N,
    busy,

    A_wr_en,
    A_index,
    A_data_in,
    A_data_out,

    B_wr_en,
    B_index,
    B_data_in,
    B_data_out,

    C_wr_en,
    C_index,
    C_data_in,
    C_data_out,

    input_offset
);


input clk;
input rst_n;
input            in_valid;
input [12:0]      K;
input [7:0]      M;
input [7:0]      N;
output           busy;

output           A_wr_en;
output reg [15:0]    A_index;
output [255:0]    A_data_in;
input  [255:0]    A_data_out;

output           B_wr_en;
output reg [15:0]    B_index;
output [255:0]    B_data_in;
input  [255:0]    B_data_out;

output reg      C_wr_en;
output reg [15:0]    C_index;
output reg [127:0]   C_data_in;
input  [127:0]   C_data_out;
input signed [31:0] input_offset;

reg [11:0] K_reg;
reg [15:0] A_sz;
wire [17:0] M_x_K = M * K;
reg [5:0] M_reg_div_4;
reg  state, next_state;
localparam   IDLE = 0, 
             INPUT = 1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) state <= IDLE;
    else state <= next_state;
end

always @(*) begin
    case(state)
        IDLE: next_state = in_valid ? INPUT : IDLE;
        INPUT: next_state = (C_wr_en && C_index == M_reg_div_4-1) ? IDLE : INPUT;
        default: next_state = IDLE;
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        K_reg <= 0;
        M_reg_div_4 <= 0;
        A_sz <= 0;
    end
    else if(state == IDLE && in_valid) begin
        K_reg <= (K >> 5);
        M_reg_div_4 <= (M) >> 2;
        A_sz <= (M_x_K) >> 5;
    end
    else begin
        K_reg <= K_reg;
        M_reg_div_4 <= M_reg_div_4;
        A_sz <= A_sz;
    end
end
assign busy = (state != IDLE);

assign A_wr_en = 0;
assign B_wr_en = 0;
assign A_data_in = 0;
assign B_data_in = 0;
// stage 1 input data
reg input_data_valid;
wire one_row_comp_done = B_index == K_reg - 1;
reg one_row_comp_done_reg;
reg one_row_comp_done_reg_delay;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        one_row_comp_done_reg <= 0;
        one_row_comp_done_reg_delay <= 0;
    end
    else begin
        one_row_comp_done_reg <= one_row_comp_done;
        one_row_comp_done_reg_delay <= one_row_comp_done_reg;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        A_index <= 0;
        B_index <= 0;
    end
    else if(state == IDLE) begin
        A_index <= 0;
        B_index <= 0;
    end
    else if(state == INPUT) begin
        A_index <= A_index < A_sz-1 ? A_index + 1 : 0;
        B_index <= B_index == K_reg - 1 ? 0 : B_index + 1;
    end
    else begin
        A_index <= 0;
        B_index <= 0;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        input_data_valid <= 0;
    end
    else if(state == INPUT) begin
        input_data_valid <= 1;
    end
    else begin
        input_data_valid <= 0;
    end
end

reg [255:0] A_reg, B_reg;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        A_reg <= 0;
        B_reg <= 0;
    end
    else  begin
        A_reg <= A_data_out;
        B_reg <= B_data_out;
    end
end

// stage 2 compute
reg signed [31:0] output_buffer;
wire signed [15:0] prod_0, prod_1, prod_2, prod_3, prod_4, prod_5, prod_6, prod_7,
                     prod_8, prod_9, prod_10, prod_11, prod_12, prod_13, prod_14, prod_15,
                     prod_16, prod_17, prod_18, prod_19, prod_20, prod_21, prod_22, prod_23,
                     prod_24, prod_25, prod_26, prod_27, prod_28, prod_29, prod_30, prod_31;
assign prod_0 =  ($signed(A_reg[7 : 0]) + input_offset)
                * $signed(B_reg[7 : 0]);
assign prod_1 =  ($signed(A_reg[15: 8]) + input_offset)
                * $signed(B_reg[15: 8]);
assign prod_2 =  ($signed(A_reg[23:16]) + input_offset)
                * $signed(B_reg[23:16]);
assign prod_3 =  ($signed(A_reg[31:24]) + input_offset)
                * $signed(B_reg[31:24]);
assign prod_4 =  ($signed(A_reg[39:32]) + input_offset)
                * $signed(B_reg[39:32]);
assign prod_5 =  ($signed(A_reg[47:40]) + input_offset)
                * $signed(B_reg[47:40]);
assign prod_6 =  ($signed(A_reg[55:48]) + input_offset)
                * $signed(B_reg[55:48]);
assign prod_7 =  ($signed(A_reg[63:56]) + input_offset)
                * $signed(B_reg[63:56]);
assign prod_8 =  ($signed(A_reg[71:64]) + input_offset)
                * $signed(B_reg[71:64]);
assign prod_9 =  ($signed(A_reg[79:72]) + input_offset)
                * $signed(B_reg[79:72]);
assign prod_10 =  ($signed(A_reg[87:80]) + input_offset)
                * $signed(B_reg[87:80]);
assign prod_11 =  ($signed(A_reg[95:88]) + input_offset)
                * $signed(B_reg[95:88]);
assign prod_12 =  ($signed(A_reg[103:96]) + input_offset)
                * $signed(B_reg[103:96]);   
assign prod_13 =  ($signed(A_reg[111:104]) + input_offset)
                * $signed(B_reg[111:104]);
assign prod_14 =  ($signed(A_reg[119:112]) + input_offset)
                * $signed(B_reg[119:112]);
assign prod_15 =  ($signed(A_reg[127:120]) + input_offset)
                * $signed(B_reg[127:120]);
assign prod_16 =  ($signed(A_reg[135:128]) + input_offset)
                * $signed(B_reg[135:128]);
assign prod_17 =  ($signed(A_reg[143:136]) + input_offset)
                * $signed(B_reg[143:136]);
assign prod_18 =  ($signed(A_reg[151:144]) + input_offset)
                * $signed(B_reg[151:144]);
assign prod_19 =  ($signed(A_reg[159:152]) + input_offset)
                * $signed(B_reg[159:152]);
assign prod_20 =  ($signed(A_reg[167:160]) + input_offset)
                * $signed(B_reg[167:160]);
assign prod_21 =  ($signed(A_reg[175:168]) + input_offset)
                * $signed(B_reg[175:168]);
assign prod_22 =  ($signed(A_reg[183:176]) + input_offset)
                * $signed(B_reg[183:176]);
assign prod_23 =  ($signed(A_reg[191:184]) + input_offset)
                * $signed(B_reg[191:184]);
assign prod_24 =  ($signed(A_reg[199:192]) + input_offset)
                * $signed(B_reg[199:192]);
assign prod_25 =  ($signed(A_reg[207:200]) + input_offset)
                * $signed(B_reg[207:200]);
assign prod_26 =  ($signed(A_reg[215:208]) + input_offset)
                * $signed(B_reg[215:208]);
assign prod_27 =  ($signed(A_reg[223:216]) + input_offset)
                * $signed(B_reg[223:216]);
assign prod_28 =  ($signed(A_reg[231:224]) + input_offset)
                * $signed(B_reg[231:224]);
assign prod_29 =  ($signed(A_reg[239:232]) + input_offset)
                * $signed(B_reg[239:232]);
assign prod_30 =  ($signed(A_reg[247:240]) + input_offset)
                * $signed(B_reg[247:240]);
assign prod_31 =  ($signed(A_reg[255:248]) + input_offset)
                * $signed(B_reg[255:248]);
wire signed [31:0] sum_prods;
assign sum_prods = prod_0 + prod_1 + prod_2 + prod_3 + prod_4 + prod_5 + prod_6 + prod_7 +
                   prod_8 + prod_9 + prod_10 + prod_11 + prod_12 + prod_13 + prod_14 + prod_15
                     + prod_16 + prod_17 + prod_18 + prod_19 + prod_20 + prod_21 + prod_22 + prod_23
                     + prod_24 + prod_25 + prod_26 + prod_27 + prod_28 + prod_29 + prod_30 + prod_31;
reg done_reg;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        output_buffer <= 0;
    end
    else if(input_data_valid) begin
        output_buffer <= one_row_comp_done_reg_delay ? 
                        sum_prods : output_buffer + sum_prods;
    end
    else begin
        output_buffer <= 0;
    end
end

// stage 3 output data
reg [1:0] out_accum_cnt;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        C_data_in <= 0;
        out_accum_cnt <= 0;
    end
    else if(state == IDLE) begin
        C_data_in <= 0;
        out_accum_cnt <= 0;
    end
    else if(one_row_comp_done_reg_delay) begin
        C_data_in <= {C_data_in[95:0], output_buffer};
        out_accum_cnt <= out_accum_cnt + 1;
    end
    else begin
        C_data_in <= C_data_in;
        out_accum_cnt <= out_accum_cnt;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        C_wr_en <= 0;
    end
    else if(state == IDLE) begin
        C_wr_en <= 0;
    end
    else if(one_row_comp_done_reg_delay && out_accum_cnt == 3) begin
        C_wr_en <= 1;
    end
    else begin
        C_wr_en <= 0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        C_index <= 0;
    end
    else if(state == IDLE) begin
        C_index <= 0;
    end
    else if(C_wr_en) begin
        C_index <= C_index + 1;
    end
    else begin
        C_index <= C_index;
    end
end
endmodule
