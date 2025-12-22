module global_buffer_bram #(parameter ADDR_BITS=8, parameter DATA_BITS=8)(
  input                      clk,
  input                      rst_n,
  input                      ram_en,
  input                      wr_en,
  input      [ADDR_BITS-1:0] index,
  input      [DATA_BITS-1:0] data_in,
  output reg [DATA_BITS-1:0] data_out
  );

  localparam SUB_DEPTH = 2**(ADDR_BITS-1);

  // 使用 (* ram_style = "block" *) 強制 Vivado 使用 BRAM 資源
  (* ram_style = "block" *) reg [DATA_BITS-1:0] gbuff0 [SUB_DEPTH-1:0];
  (* ram_style = "block" *) reg [DATA_BITS-1:0] gbuff1 [SUB_DEPTH-1:0];

  // 為了確保 BRAM 推論成功，建議將讀取邏輯寫得更單純
  reg [DATA_BITS-1:0] out0, out1;
  reg sel_reg;

  always @ (negedge clk) begin
    if (ram_en) begin
      // 寫入邏輯
      if(wr_en) begin
        if(index[ADDR_BITS-1]) 
          gbuff1[index[ADDR_BITS-2:0]] <= data_in;
        else                   
          gbuff0[index[ADDR_BITS-2:0]] <= data_in;
      end
      
      // 讀取邏輯：讓 BRAM 內部先輸出，外部再做選擇
      out0 <= gbuff0[index[ADDR_BITS-2:0]];
      out1 <= gbuff1[index[ADDR_BITS-2:0]];
      sel_reg <= index[ADDR_BITS-1];
    end
  end

  // 根據暫存的位址高位選擇輸出
  always @ (*) begin
    data_out = sel_reg ? out1 : out0;
  end

endmodule