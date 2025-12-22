import numpy as np
import tensorflow as tf

def generate_header(model_path, output_header):
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    details = interpreter.get_tensor_details()
    
    found_any = False
    with open(output_header, 'w') as f:
        f.write("#ifndef WEIGHTS_DATA_H\n#define WEIGHTS_DATA_H\n\n")
        f.write("#include <stdint.h>\n\n")
        
        conv_layer_idx = 0
        for detail in details:
            shape = detail['shape']
            name = detail['name']
            
            if len(shape) == 4 and 'Conv2D' in name:
                try:
                    weights = interpreter.get_tensor(detail['index'])
                except ValueError:
                    continue
                
                if weights.dtype != np.int8:
                    continue

                print(f"正在處理權重: {name}, 形狀: {shape}")
                
                oc, h, w, ic = shape
                k_orig = h * w * ic
                
                # --- 關鍵修改：將 K 對齊到 32 的倍數 ---
                cast32_k = (k_orig + 31) // 32 * 32 
                # --------------------------------------
                
                var_name = f"conv_layer_{conv_layer_idx}"
                f.write(f"// Original Name: {name} | K aligned to 32\n")
                f.write(f"static const int8_t {var_name}_weights[{oc}][{cast32_k}] __attribute__((aligned(16))) = {{\n")
                
                weights_flat = weights.reshape(oc, -1)
                for i in range(oc):
                    row = weights_flat[i]
                    # 補零到 32 的倍數
                    padded_row = np.pad(row, (0, cast32_k - k_orig), 'constant', constant_values=0)
                    f.write("    {" + ", ".join(map(str, padded_row)) + "},\n")
                
                f.write("};\n\n")
                conv_layer_idx += 1
                found_any = True
        
        f.write("#endif // WEIGHTS_DATA_H\n")
    
    print(f"成功！已產出 K 對齊至 32 的權重檔。")

generate_header("wav2letter_pruned_int8.tflite", "../../tensorflow/lite/kernels/internal/reference/integer_ops/weights_data.h")