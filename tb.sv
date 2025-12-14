`timescale 1ns/1ps

module tb_cfu;

  // ===== clock / reset =====
  reg clk = 0;
  always #5 clk = ~clk;          // 100 MHz
  reg reset = 1;

  // ===== CFU interface =====
  reg               cmd_valid;
  wire              cmd_ready;
  reg  [9:0]        cmd_payload_function_id;
  reg  [31:0]       cmd_payload_inputs_0;
  reg  [31:0]       cmd_payload_inputs_1;
  wire              rsp_valid;
  reg               rsp_ready = 1'b1;      // always ready
  wire [31:0]       rsp_payload_outputs_0;

  // ===== DUT =====
  Cfu dut (
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_payload_function_id(cmd_payload_function_id),
    .cmd_payload_inputs_0(cmd_payload_inputs_0),
    .cmd_payload_inputs_1(cmd_payload_inputs_1),
    .rsp_valid(rsp_valid),
    .rsp_ready(rsp_ready),
    .rsp_payload_outputs_0(rsp_payload_outputs_0),
    .reset(reset),
    .clk(clk)
  );

  // ===== Storage =====
  // 為了安全起見，開大一點的 buffer
  localparam MAX_A_WORDS = 200000; 
  localparam MAX_B_WORDS = 2000;
  localparam MAX_C_WORDS = 256;

  reg [31:0] A_mem   [0:MAX_A_WORDS-1];
  reg [31:0] B_mem   [0:MAX_B_WORDS-1];
  reg [31:0] C_ans   [0:MAX_C_WORDS-1];
  reg [31:0] C_out   [0:MAX_C_WORDS-1];

  integer i;

  // ===== GTKWave dump =====
  initial begin
    $dumpfile("cfu_tb.vcd");
    $dumpvars(0, tb_cfu);
  end

  // ===== task: 發送計算指令 =====
  task send_cmd;
    input [31:0] in0;
    input [31:0] in1;
    input [6:0] funct7;
  begin
    cmd_payload_function_id = {funct7, 3'b000}; 
    cmd_payload_inputs_0    = in0;
    cmd_payload_inputs_1    = in1;
    cmd_valid               = 1'b1;

    // Handshake
    @(posedge clk);
    while (~cmd_ready) @(posedge clk);
    cmd_valid = 1'b0;
    while (!(rsp_valid && rsp_ready)) @(posedge clk);
    @(posedge clk);
  end
  endtask

  // ===== task: 發送讀回指令 =====
  task send_cmd_C;
    input [15:0] index_i; // unused logic in task, placeholders
    input [15:0] index_j; // unused logic in task, placeholders
    input [6:0] funct7;
    input [31:0] output_idx; // 存入 C_out 的位置
  begin
    // 模擬軟體延遲 (Optional)
    repeat(2) @(posedge clk);

    cmd_payload_function_id = {funct7, 3'b000}; 
    cmd_payload_inputs_0    = 32'h0;
    cmd_payload_inputs_1    = 32'h0;
    cmd_valid               = 1'b1;

    // Handshake
    @(posedge clk);
    while (~cmd_ready) @(posedge clk);
    cmd_valid = 1'b0;
    @(posedge clk);
    while (!(rsp_valid && rsp_ready)) @(posedge clk);

    // 存結果
    C_out[output_idx] = rsp_payload_outputs_0;
    @(posedge clk);
  end
  endtask

  // ===== 測試案例參數 =====
  integer num_cases = 13;
  reg [8*10:1] case_names [0:12]; // 用來顯示 L1, L2...
  integer M_vals [0:12];
  integer K_vals [0:12];
  integer Input_offset_vals [0:12];
  integer N_vals [0:12]; 

  initial begin
    // 依照順序對應 1.txt ~ 13.txt
    case_names[0] = "L1";   M_vals[0]=148; K_vals[0]=1340; Input_offset_vals[0]=3;   N_vals[0]=2;  // 1.txt
    case_names[1] = "L2";   M_vals[1]=148; K_vals[1]=1052; Input_offset_vals[1]=75;  N_vals[1]=2;  // 2.txt
    case_names[2] = "L3";   M_vals[2]=148; K_vals[2]=1236; Input_offset_vals[2]=72;  N_vals[2]=2;  // 3.txt
    case_names[3] = "L4";   M_vals[3]=148; K_vals[3]=1064; Input_offset_vals[3]=33;  N_vals[3]=2;  // 4.txt
    case_names[4] = "L5";   M_vals[4]=148; K_vals[4]=1108; Input_offset_vals[4]=80;  N_vals[4]=2;  // 5.txt
    case_names[5] = "L6";   M_vals[5]=148; K_vals[5]=1064; Input_offset_vals[5]=72;  N_vals[5]=2;  // 6.txt
    case_names[6] = "L7";   M_vals[6]=148; K_vals[6]=1276; Input_offset_vals[6]=68;  N_vals[6]=2;  // 7.txt
    case_names[7] = "L8";   M_vals[7]=148; K_vals[7]=1020; Input_offset_vals[7]=56;  N_vals[7]=2;  // 8.txt
    case_names[8] = "L9-1"; M_vals[8]=52;  K_vals[8]=4912; Input_offset_vals[8]=90;  N_vals[8]=2; // 9.txt
    case_names[9] = "L9-2"; M_vals[9]=52;  K_vals[9]=4912; Input_offset_vals[9]=90;  N_vals[9]=2; // 10.txt
    case_names[10]="L9-3";  M_vals[10]=44; K_vals[10]=4912; Input_offset_vals[10]=90; N_vals[10]=2;// 11.txt
    case_names[11]="L10";   M_vals[11]=148; K_vals[11]=1364; Input_offset_vals[11]=84; N_vals[11]=2;// 12.txt
    case_names[12]="L11";   M_vals[12]=148; K_vals[12]=1220; Input_offset_vals[12]=66; N_vals[12]=2;// 13.txt

  end

  // ===== Main Flow =====
  integer case_idx, jdx;
  integer m_curr, k_curr;
  integer m_aligned, k_aligned;
  integer num_in_a, num_in_b, num_out;
  integer mism;
  integer total_errors = 0;
  integer total_pass = 0;
  reg [8*64:1] fname_a, fname_b, fname_ans;

  initial begin
    // Init
    cmd_valid = 0;
    cmd_payload_function_id = 0;
    cmd_payload_inputs_0 = 0;
    cmd_payload_inputs_1 = 0;
    
    #10; 

    // 迭代 0 ~ 12 (對應檔案 1 ~ 13)
    for (case_idx = 0; case_idx < num_cases; case_idx = case_idx + 1) begin
        // 1. 參數計算
        m_curr = M_vals[case_idx];
        k_curr = K_vals[case_idx];
        
        // Padding: 向上取 4 的倍數
        m_aligned = m_curr;
        k_aligned = k_curr;

        // 計算 Input Words (除以 4)
        num_in_b = k_aligned / 4;
        num_in_a = (m_aligned * k_aligned) / 4;
        num_out  = m_curr;

        // 2. 顯示當前測試資訊
        $display("---------------------------------------------------");
        // case_idx + 1 就是檔案編號
        $display("Running Case %0d (%0s): M=%0d (align %0d), K=%0d (align %0d)", 
                case_idx + 1, case_names[case_idx], m_curr, m_aligned, k_curr, k_aligned);
        for (jdx = 0; jdx < N_vals[case_idx]; jdx = jdx + 1) begin


          // 3. Reset DUT
          reset = 1;
          repeat (10) @(posedge clk);
          reset = 0;
          repeat (5) @(posedge clk);

          // 4. 讀檔 (使用 case_idx + 1 來產生 1.txt, 2.txt ...)
          $sformat(fname_a,   "./output/A_arr_%0d_%0d.txt", case_idx + 1, jdx);
          $sformat(fname_b,   "./output/B_arr_%0d_%0d.txt", case_idx + 1, jdx);
          $sformat(fname_ans, "./output/C_ans_%0d_%0d.txt", case_idx + 1, jdx);
          
          // 檢查檔案是否存在 (Optional debug info)
          // $display("Loading: %0s, %0s", fname_a, fname_b);

          $readmemh(fname_a, A_mem);
          $readmemh(fname_b, B_mem);
          $readmemh(fname_ans, C_ans);

          // 5. 設定參數 (funct7=3: Set Params, funct7=4: Reset Offset)
          send_cmd(m_curr, k_curr, 3); 
          send_cmd(0, Input_offset_vals[case_idx], 4);

          // 6. 傳送 Weights (B)
          for (i = 0; i < num_in_b; i = i + 1) begin
              send_cmd(B_mem[i], 0, 1);
          end

          // 7. 傳送 Activations (A)
          for (i = 0; i < num_in_a; i = i + 1) begin
              send_cmd(A_mem[i], 0, 0);
          end

          // 8. 讀回結果 (funct7=2)
          @(posedge clk);
          for (i = 0; i < num_out; i = i + 1) begin
              send_cmd_C(0, i, 2, i);
          end

          // 9. 比對
          mism = 0;
          for (i = 0; i < num_out; i = i + 1) begin
              if (C_out[i] !== C_ans[i]) begin
                  $display("[FAIL] Case %0d (%0s) @ out[%0d]: got=%08h, exp=%08h", 
                          case_idx + 1, case_names[case_idx], i, C_out[i], C_ans[i]);
                  mism = mism + 1;
              end
          end

          if (mism == 0) begin
              $display("[PASS] Case %0d (%0s) passed.", case_idx + 1, case_names[case_idx]);
              total_pass = total_pass + 1;
          end else begin
              $display("[FAIL] Case %0d (%0s) had %0d mismatches.", case_idx + 1, case_names[case_idx], mism);
              total_errors = total_errors + 1;
          end
          
          // Clear Output Buffer
          for(i=0; i<num_out; i=i+1) C_out[i] = 32'hx;
        end
    end

    $display("===================================================");
    if (total_errors == 0) 
        $display("ALL %0d CASES PASSED!", total_pass);
    else 
        $display("TOTAL FAILED CASES: %0d / %0d", total_errors, total_pass + total_errors);
    $display("===================================================");

    $finish;
  end

endmodule