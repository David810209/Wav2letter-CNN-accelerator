module VPU(
    clk,
    rst_n,

    in_valid,
    K,
    M,
    K_nonzero,
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
    D_wr_en,
    D_index,
    D_data_in,
    D_data_out,

    input_offset
);


input clk;
input rst_n;
input            in_valid;
input [12:0]      K;
input [7:0]      M;
input [12:0]      K_nonzero;
output           busy;

output           A_wr_en;
output reg [15:0]    A_index;
output [31:0]    A_data_in;
input  [31:0]    A_data_out;

output           B_wr_en;
output reg [15:0]    B_index;
output [31:0]    B_data_in;
input  [31:0]    B_data_out;

output reg      C_wr_en;
output reg [15:0]    C_index;
output reg [127:0]   C_data_in;
input  [127:0]   C_data_out;

output           D_wr_en;
output reg [15:0]    D_index;
output [63:0]    D_data_in;
input  [63:0]    D_data_out;
input signed [31:0] input_offset;

reg [11:0] K_reg_div_4;
reg [11:0] K_nonzero_reg_div_4;
reg [5:0] M_reg_div_4;
reg cal_data_valid;
reg input_valid;
wire one_row_comp_done;
reg one_row_comp_done_reg;
reg one_row_comp_done_reg_delay;
reg [1:0] input_cnt;
reg [15:0] index_sel;
reg [15:0] index_sel_reg;
wire [15:0] index_div_4;
wire [1:0] index_offset;
reg [15:0] M_base_index;
reg [1:0] cal_cnt;
reg [1:0] addr_sel_cnt;
reg [31:0] A_reg, B_reg;
reg [63:0] D_reg;
reg  state, next_state;
//FSM
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
// store K, M
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        K_reg_div_4 <= 0;
        M_reg_div_4 <= 0;
        K_nonzero_reg_div_4 <= 0;
    end
    else if(state == IDLE && in_valid) begin
        K_reg_div_4 <= (K >> 2);
        M_reg_div_4 <= (M) >> 2;
        K_nonzero_reg_div_4 <= (K_nonzero >> 2);
    end
    else begin
        K_reg_div_4 <= K_reg_div_4;
        M_reg_div_4 <= M_reg_div_4;
        K_nonzero_reg_div_4 <= K_nonzero_reg_div_4;
    end
end
// register input A,B,D
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        A_reg <= 0;
        B_reg <= 0;
        D_reg <= 0;
    end
    else  begin
        A_reg <= A_data_out;
        B_reg <= B_data_out;
        D_reg <= D_data_out;
    end
end
assign busy = (state != IDLE);

assign A_wr_en = 0;
assign B_wr_en = 0;
assign A_data_in = 0;
assign B_data_in = 0;
assign D_wr_en = 0;
assign D_data_in = 0;
//stage 0 get index

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        input_cnt <= 0;
    end
    else if(state == IDLE) begin
        input_cnt <= 0;
    end
    else if(state == INPUT) begin
        input_cnt <= input_cnt + 1;
    end
    else begin
        input_cnt <= 0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        D_index <= 0;
    end
    else if(state == IDLE) begin
        D_index <= 0;
    end
    else if(state == INPUT && input_cnt == 3) begin
        D_index <= D_index == K_nonzero_reg_div_4 - 1 ? 0 : D_index + 1;
    end
    else begin
        D_index <= D_index;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        input_valid <= 0;
    end
    else if(state == INPUT) begin
        input_valid <= 1;
    end
    else begin
        input_valid <= 0;
    end
end
// stage 1 input data
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        addr_sel_cnt <= 0;
    end
    else if(input_valid) begin
        addr_sel_cnt <= addr_sel_cnt + 1;
    end
    else begin
        addr_sel_cnt <= 0;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        B_index <= 0;
    end
    else begin
        B_index <= D_index;
    end
end
always @(*) begin
    case(addr_sel_cnt)
        2'b00: index_sel = D_reg[63:48];
        2'b01: index_sel = D_reg[47:32];
        2'b10: index_sel = D_reg[31:16];
        2'b11: index_sel = D_reg[15:0];
        default: index_sel = 0;
    endcase
end
assign index_div_4 = index_sel >> 2;
assign index_offset = index_sel[1:0];
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        M_base_index <= 0;
    end
    else if(state == IDLE) begin
        M_base_index <= 0;
    end
    else if(state == INPUT && one_row_comp_done) begin
        M_base_index <= M_base_index + K_reg_div_4;
    end
    else begin
        M_base_index <= M_base_index;
    end
end
always @(*) begin
    A_index = M_base_index + index_div_4;
end

// stage 2 compute
assign one_row_comp_done = B_index == K_nonzero_reg_div_4 - 1 && addr_sel_cnt == 3;
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
        cal_data_valid <= 0;
    end
    else begin
        cal_data_valid <= input_valid;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        index_sel_reg <= 0;
    end
    else begin
        index_sel_reg <= index_sel;
    end
end
reg signed [31:0] output_buffer;
wire signed [15:0] prod_0;
reg [7:0] A_data_sel;
reg [7:0] B_data_sel;
always @(*) begin
    case(index_sel_reg[1:0])
        2'b00:A_data_sel = A_reg[31:24];
        2'b01:A_data_sel = A_reg[23:16];
        2'b10:A_data_sel = A_reg[15:8];
        2'b11:A_data_sel = A_reg[7:0];
        default: A_data_sel = 0;
    endcase
end
always @(*) begin
    case(cal_cnt)
        2'b00:B_data_sel = B_reg[31:24];
        2'b01:B_data_sel = B_reg[23:16];
        2'b10:B_data_sel = B_reg[15:8];
        2'b11:B_data_sel = B_reg[7:0];
        default: B_data_sel = 0;
    endcase
end

assign prod_0 =  ($signed(A_data_sel) + input_offset)
                * $signed(B_data_sel);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        output_buffer <= 0;
        cal_cnt <= 0;
    end
    else if(cal_data_valid) begin
        cal_cnt <= cal_cnt + 1;
        output_buffer <= one_row_comp_done_reg_delay ? 
                        prod_0 : output_buffer + prod_0;
    end
    else begin
        cal_cnt <= 0;
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
