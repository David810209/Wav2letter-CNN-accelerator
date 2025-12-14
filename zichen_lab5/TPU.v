
module TPU(
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
input [8:0]      K;
input [8:0]      M;
input [8:0]      N;
output           busy;

output           A_wr_en;
output  [15:0]    A_index;
output [31:0]    A_data_in;
input  [31:0]    A_data_out;

output           B_wr_en;
output  [15:0]    B_index;
output [31:0]    B_data_in;
input  [31:0]    B_data_out;

output           C_wr_en;
output reg [15:0]    C_index;
output [127:0]   C_data_in;
input  [127:0]   C_data_out;
input signed [31:0] input_offset;

reg [15:0] C_cnt;

//* Implement your design here

wire compute_done;
reg [8:0] K_reg, M_reg_div_4, N_reg_div_4;
reg [3:0] M_rem_reg;
reg [2:0] state, next_state;
reg [1:0] input_cnt;
reg [15:0] A_cnt, B_cnt;
reg [15:0] A_round_cnt, B_round_cnt;
reg [15:0] round_cnt;
wire fetch_end;
wire is_last_M_block;
wire is_last_N_block;
reg [3:0] compute_cnt;
reg [31:0] A_buffer [0:3];
reg [31:0] B_buffer [0:3];

reg signed[7:0] pe_vertical_data_i [0:15];
reg signed[7:0] pe_horizontal_data_i [0:15];
wire signed[7:0] pe_vertical_data_o [0:15];
wire signed[7:0] pe_horizontal_data_o [0:15];
wire signed[31:0] pe_result_o [0:15];
assign is_last_M_block = A_round_cnt == (M_reg_div_4);
assign is_last_N_block = B_round_cnt == (N_reg_div_4);
localparam   IDLE = 0, 
             INPUT = 1, 
             COMPUTE = 2, 
             OUTPUT_C = 3,
             PENDING = 4;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) state <= IDLE;
    else state <= next_state;
end

always @(*) begin
    case(state)
        IDLE: next_state = in_valid ? INPUT : IDLE;
        INPUT: next_state = (input_cnt == 3) ? COMPUTE : INPUT;
        COMPUTE: next_state = compute_cnt == 11 ? ((fetch_end) ? OUTPUT_C : INPUT) : COMPUTE;
        OUTPUT_C: next_state = is_last_M_block ? C_cnt == M_rem_reg - 1 ? PENDING : OUTPUT_C :
                                                        (C_cnt == 3) ? PENDING : OUTPUT_C;
        PENDING: next_state = (is_last_M_block && is_last_N_block) ? IDLE : INPUT;
        default: next_state = IDLE;
    endcase
end

assign A_wr_en = 0;
assign B_wr_en = 0;
assign A_data_in = 0;
assign B_data_in = 0;

assign A_index = A_cnt + input_cnt;
assign B_index = B_cnt + input_cnt;

assign fetch_end = round_cnt >= (K_reg);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        A_cnt <= 0;
        B_cnt <= 0;
    end
    else if(state == IDLE) begin
        A_cnt <= 0;
        B_cnt <= 0;
    end
    else if(state == COMPUTE && compute_cnt == 11) begin
        A_cnt <= fetch_end ? 
                 is_last_M_block ? 0 : (A_round_cnt+1) * K_reg :
                 A_cnt + 4;
        B_cnt <= fetch_end ? 
                 is_last_M_block ? (B_round_cnt+1) * K_reg : B_round_cnt * K_reg :
                 B_cnt + 4;
    end
    else begin
        A_cnt <= A_cnt;
        B_cnt <= B_cnt;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        A_round_cnt <= 0;
        B_round_cnt <= 0;
    end
    else if(state == PENDING) begin
        A_round_cnt <= is_last_M_block ? 0 : A_round_cnt + 1;
        B_round_cnt <= is_last_M_block ? 
                        is_last_N_block ? 0 : B_round_cnt + 1 
                                : B_round_cnt;
    end
    else begin
        A_round_cnt <= A_round_cnt;
        B_round_cnt <= B_round_cnt;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) input_cnt <= 0;
    else if(state == INPUT)input_cnt <= input_cnt + 1;
    else input_cnt <= 0;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) round_cnt <= 0;
    else if(state == PENDING && fetch_end) round_cnt <= 0;
    else if(state == INPUT)round_cnt <= round_cnt + 1;
    else round_cnt <= round_cnt;
end

integer idx;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
       for(idx = 0; idx < 4; idx = idx + 1) begin
           A_buffer[idx] <= 0;
           B_buffer[idx] <= 0;
       end
    end
    else if(state == INPUT) begin
        A_buffer[input_cnt] <= fetch_end ? 0 : A_data_out;
        B_buffer[input_cnt] <= fetch_end ? 0 : B_data_out;
    end
    else begin
       for(idx = 0; idx < 4; idx = idx + 1) begin
           A_buffer[idx] <= A_buffer[idx];
           B_buffer[idx] <= B_buffer[idx];
       end
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) compute_cnt <= 12;
    else if((state == INPUT && input_cnt > 1) || state == COMPUTE )compute_cnt <= compute_cnt + 1;
    else if(state == INPUT && input_cnt == 1) compute_cnt <= 0;
    else compute_cnt <= compute_cnt;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        K_reg <= 0;
        M_reg_div_4 <= 0;
        N_reg_div_4 <= 0;
        M_rem_reg <= 0;
    end
    else if(state == IDLE && in_valid) begin
        K_reg <= K;
        M_reg_div_4 <= (M - 1) >> 2;
        N_reg_div_4 <= (N - 1) >> 2;
        M_rem_reg <= M % 4 == 0 ? 4 : M % 4;
    end
    else begin
        K_reg <= K_reg;
        M_reg_div_4 <= M_reg_div_4;
        N_reg_div_4 <= N_reg_div_4;
        M_rem_reg <= M_rem_reg;
    end
end
assign busy = (state != IDLE);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pe_horizontal_data_i[0] <= 0;
        pe_horizontal_data_i[4] <= 0;
        pe_horizontal_data_i[8] <= 0;
        pe_horizontal_data_i[12] <= 0;
        pe_vertical_data_i[0] <= 0;
        pe_vertical_data_i[1] <= 0;
        pe_vertical_data_i[2] <= 0;
        pe_vertical_data_i[3] <= 0;
    end
    else begin
        pe_horizontal_data_i[0] <= compute_cnt == 0 ? A_buffer[0][31:24] : 
                                  compute_cnt == 1 ? A_buffer[1][31:24] : 
                                  compute_cnt == 2 ? A_buffer[2][31:24] : 
                                  compute_cnt == 3 ? A_buffer[3][31:24] : 0;
        pe_horizontal_data_i[4] <= compute_cnt == 1 ? A_buffer[0][23:16] : 
                                        compute_cnt == 2 ? A_buffer[1][23:16] : 
                                        compute_cnt == 3 ? A_buffer[2][23:16] : 
                                        compute_cnt == 4 ? A_buffer[3][23:16] : 0;
        pe_horizontal_data_i[8] <= compute_cnt == 2 ? A_buffer[0][15:8] : 
                                        compute_cnt == 3 ? A_buffer[1][15:8] : 
                                        compute_cnt == 4 ? A_buffer[2][15:8] : 
                                        compute_cnt == 5 ? A_buffer[3][15:8] : 0;
        pe_horizontal_data_i[12] <= compute_cnt == 3 ? A_buffer[0][7:0] : 
                                        compute_cnt == 4 ? A_buffer[1][7:0] : 
                                        compute_cnt == 5 ? A_buffer[2][7:0] : 
                                        compute_cnt == 6 ? A_buffer[3][7:0] : 0;

        pe_vertical_data_i[0] <= compute_cnt == 0 ? B_buffer[0][31:24] : 
                                        compute_cnt == 1 ? B_buffer[1][31:24] : 
                                        compute_cnt == 2 ? B_buffer[2][31:24] : 
                                        compute_cnt == 3 ? B_buffer[3][31:24] : 0;
        pe_vertical_data_i[1] <= compute_cnt == 1 ? B_buffer[0][23:16] : 
                                        compute_cnt == 2 ? B_buffer[1][23:16] : 
                                        compute_cnt == 3 ? B_buffer[2][23:16] : 
                                        compute_cnt == 4 ? B_buffer[3][23:16] : 0;
        pe_vertical_data_i[2] <= compute_cnt == 2 ? B_buffer[0][15:8] : 
                                        compute_cnt == 3 ? B_buffer[1][15:8] : 
                                        compute_cnt == 4 ? B_buffer[2][15:8] : 
                                        compute_cnt == 5 ? B_buffer[3][15:8] : 0;
        pe_vertical_data_i[3] <= compute_cnt == 3 ? B_buffer[0][7:0] : 
                                        compute_cnt == 4 ? B_buffer[1][7:0] : 
                                        compute_cnt == 5 ? B_buffer[2][7:0] : 
                                        compute_cnt == 6 ? B_buffer[3][7:0] : 0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        C_index <= 0;
    end
    else if(state == IDLE) begin
        C_index <= 0;
    end
    else if(state == OUTPUT_C) begin
        C_index <= C_index + 1;
    end
    else begin
        C_index <= C_index;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) C_cnt <= 0;
    else if(state == OUTPUT_C) C_cnt <= C_cnt + 1;
    else C_cnt <= 0;
end

assign C_wr_en = (state == OUTPUT_C);
assign C_data_in = C_cnt == 0 ? {pe_result_o[0], pe_result_o[1], pe_result_o[2], pe_result_o[3]} :
                  C_cnt == 1 ? {pe_result_o[4], pe_result_o[5], pe_result_o[6], pe_result_o[7]} :
                  C_cnt == 2 ? {pe_result_o[8], pe_result_o[9], pe_result_o[10], pe_result_o[11]} :
                  C_cnt == 3 ? {pe_result_o[12], pe_result_o[13], pe_result_o[14], pe_result_o[15]} : 0;
always @(*) begin
 pe_horizontal_data_i[1] = pe_horizontal_data_o[0]; 
 pe_horizontal_data_i[2] = pe_horizontal_data_o[1]; 
 pe_horizontal_data_i[3] = pe_horizontal_data_o[2]; 
 pe_horizontal_data_i[5] = pe_horizontal_data_o[4]; 
 pe_horizontal_data_i[6] = pe_horizontal_data_o[5]; 
 pe_horizontal_data_i[7] = pe_horizontal_data_o[6]; 
 pe_horizontal_data_i[9] = pe_horizontal_data_o[8]; 
 pe_horizontal_data_i[10] = pe_horizontal_data_o[9]; 
 pe_horizontal_data_i[11] = pe_horizontal_data_o[10]; 
 pe_horizontal_data_i[13] = pe_horizontal_data_o[12]; 
 pe_horizontal_data_i[14] = pe_horizontal_data_o[13]; 
 pe_horizontal_data_i[15] = pe_horizontal_data_o[14]; 

 pe_vertical_data_i[4] = pe_vertical_data_o[0];
 pe_vertical_data_i[8] = pe_vertical_data_o[4];
 pe_vertical_data_i[12] = pe_vertical_data_o[8];
 pe_vertical_data_i[5] = pe_vertical_data_o[1];
 pe_vertical_data_i[9] = pe_vertical_data_o[5];
 pe_vertical_data_i[13] = pe_vertical_data_o[9];
 pe_vertical_data_i[6] = pe_vertical_data_o[2];
 pe_vertical_data_i[10] = pe_vertical_data_o[6];
 pe_vertical_data_i[14] = pe_vertical_data_o[10];
 pe_vertical_data_i[7] = pe_vertical_data_o[3];
 pe_vertical_data_i[11] = pe_vertical_data_o[7];
 pe_vertical_data_i[15] = pe_vertical_data_o[11];
end
genvar  i;
generate
    for (i = 0; i < 16; i = i + 1) begin : PE_INSTANCES
        PE pe_inst (
            .clk(clk),
            .rst_n(rst_n),
            .flush_i((state == PENDING || state == IDLE)),
            .vertical_data_i(pe_vertical_data_i[i]),
            .horizontal_data_i(pe_horizontal_data_i[i]),
            .vertical_data_o(pe_vertical_data_o[i]),
            .horizontal_data_o(pe_horizontal_data_o[i]),
            .result_o(pe_result_o[i]),
            .input_offset(input_offset)
        );
    end
endgenerate

endmodule

module PE(
    input clk,
    input rst_n,
    input       flush_i,
    input signed [31:0] input_offset,
    input signed[7:0] vertical_data_i,
    input signed[7:0] horizontal_data_i,
    output reg signed[7:0] vertical_data_o,
    output reg signed[7:0] horizontal_data_o,
    output reg signed[31:0] result_o
);

always @(posedge clk or negedge rst_n) begin
   if(!rst_n)begin
        vertical_data_o <= 8'b0;
        horizontal_data_o <= 8'b0;
        result_o <= 32'b0;
     end else begin
            vertical_data_o <= vertical_data_i;
            horizontal_data_o <= horizontal_data_i;
            result_o <= flush_i ? 0 : vertical_data_i * (horizontal_data_i + input_offset) + result_o; 
    end
end

endmodule