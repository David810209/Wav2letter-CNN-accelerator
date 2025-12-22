/* Copyright 2019 The TensorFlow Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/
#ifndef TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_
#define TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_

#include <algorithm>

#include "tensorflow/lite/kernels/internal/common.h"
#include "tensorflow/lite/kernels/internal/portable_tensor_utils.h"
#include "playground_util/print_params.h"
#include "cfu.h"
#include "perf.h"
#include <cstdio>
#include "weights_data.h"
static int current_conv_layer_id = 0;
namespace tflite {
namespace reference_integer_ops {

// Fixed-point per-channel-quantization convolution reference kernel.
inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int8_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const int32_t* bias_data, const RuntimeShape& output_shape,
    int8_t* output_data) {
    // print_conv_params(params, input_shape, filter_shape, output_shape);
      perf_enable_counter(6);
      uint64_t total_start_time = perf_get_mcycle64();
  const int K_max = 8000; // filter_w * filter_h * input_depth. -> max(layer # 2) = 1 * 1 * 300 = 300
  const int M_max = 148; // out_w * out_h. -> max(layer # 1) = 45 * 18 = 810
  // const int N_max = 2000; // out_ch -> max(layer #1) = 300
  alignas(4) int8_t im2col[M_max][K_max];
  // alignas(4) int8_t kernel[N_max][K_max];
  static const int8_t* all_layer_weights[] = {
    &conv_layer_0_weights[0][0], &conv_layer_1_weights[0][0],
    &conv_layer_2_weights[0][0], &conv_layer_3_weights[0][0],
    &conv_layer_4_weights[0][0], &conv_layer_5_weights[0][0],
    &conv_layer_6_weights[0][0], &conv_layer_7_weights[0][0],
    &conv_layer_8_weights[0][0], &conv_layer_9_weights[0][0],
    &conv_layer_10_weights[0][0]
};
  const int8_t* kernel = all_layer_weights[current_conv_layer_id];
  current_conv_layer_id++;
  if(current_conv_layer_id == 11) current_conv_layer_id = 0;

  // Get parameters.
  const int32_t input_offset = params.input_offset;  // r = s(q - Z)
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;
  const int32_t output_offset = params.output_offset;

  // Set min and max value of the output.
  const int32_t output_activation_min = params.quantized_activation_min;
  const int32_t output_activation_max = params.quantized_activation_max;

  // Consistency check.
  TFLITE_DCHECK_LE(output_activation_min, output_activation_max);
  TFLITE_DCHECK_EQ(input_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(filter_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(output_shape.DimensionsCount(), 4);
  // const int batches = MatchingDim(input_shape, 0, output_shape, 0);
  const int input_depth = input_shape.Dims(3);
  const int output_depth = MatchingDim(filter_shape, 0, output_shape, 3);
  if (bias_data) {
    TFLITE_DCHECK_EQ(bias_shape.FlatSize(), output_depth);
  }

  // Check dimensions of the tensors.
  const int input_height = input_shape.Dims(1);
  const int input_width = input_shape.Dims(2);
  const int filter_height = filter_shape.Dims(1);
  const int filter_width = filter_shape.Dims(2);
  const int filter_input_depth = filter_shape.Dims(3);
  // const int groups = input_depth / filter_input_depth;
  TFLITE_DCHECK_EQ(input_depth % filter_input_depth, 0);
  // const int filters_per_group = output_depth / groups;
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);
  int M = output_height * output_width;
  int N = output_depth;
  int K = filter_height * filter_width * filter_input_depth;
  int cast32_K = (K + 31) /32 *32;
  uint64_t filter_load_time = 0;
  uint64_t image_load_time = 0;
  uint64_t compute_and_out_time = 0;
  uint64_t start_time, end_time;
  uint64_t convert_image_time = 0;
  uint64_t convert_filter_time = 0;
  // convert image
  start_time = perf_get_mcycle64();
  const int input_width_stride = input_width * input_depth;
  int8_t pad_val = static_cast<int8_t>(-input_offset);

  int patch_i = 0;
  for (int out_y = 0; out_y < output_height; ++out_y) {
      const int in_y_origin = (out_y * stride_height) - pad_height;
      
      for (int out_x = 0; out_x < output_width; ++out_x) {
          const int in_x_origin = (out_x * stride_width) - pad_width;
          
          int8_t* patch_row_ptr = &im2col[patch_i][0];

          for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
              const int in_y = in_y_origin + dilation_height_factor * filter_y;
              const bool y_in = (in_y >= 0) && (in_y < input_height);
              
              const int8_t* in_row_base = input_data + (in_y * input_width_stride);

              for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
                  const int in_x = in_x_origin + dilation_width_factor * filter_x;
                  const bool x_in = (in_x >= 0) && (in_x < input_width);

                  if (y_in && x_in) {
                      const int8_t* in_ptr = in_row_base + (in_x * input_depth);
                      for (int c = 0; c < input_depth; ++c) {
                          *patch_row_ptr++ = *in_ptr++;
                      }
                  } else {
                      for (int c = 0; c < input_depth; ++c) {
                          *patch_row_ptr++ = pad_val;
                      }
                  }
              }
          }
          patch_i++;
      }
  }
  if(K == 1750){
    for(int i = 0;i < M;i++){
      for(int j = 1750;j < 1760;j++){
        im2col[i][j] = 0;
      }
    }
  }
  else if(K == 1872){
    for(int i = 0;i < M;i++){
      for(int j = 1872;j < 1888;j++){
        im2col[i][j] = 0;
      }
    }
  }
  else if(K == 2000){
    for(int i = 0;i < M;i++){
      for(int j = 2000;j < 2016;j++){
        im2col[i][j] = 0;
      }
    }
  }
  end_time = perf_get_mcycle64();
  convert_image_time += end_time - start_time;
  // convert filter
  // start_time = perf_get_mcycle64();
  // int filter_j = 0; // output_depth
  // for(int out_channel = 0; out_channel < output_depth;++out_channel){
  //   int filter_i = 0; // filter_w * filter_h * input_depth
  //   for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
  //     for (int filter_x = 0; filter_x < filter_width; ++filter_x) {

  //       for (int in_channel = 0; in_channel < filter_input_depth;
  //             ++in_channel) {
  //         kernel[filter_j][filter_i++] = static_cast<int8_t>(filter_data[Offset(
  //             filter_shape, out_channel, filter_y, filter_x, in_channel)]);
  //       }
  //     }
  //   }
  //   filter_j++;
  // } 
  // if(K == 1750){
  //     for(int i = 0;i < N;i++){ 
  //       for(int j = 1750;j < 1752;j++){ 
  //         kernel[i][j] = 0; 
  //       }
  //    }
  // }
  // end_time = perf_get_mcycle64();
  // convert_filter_time += end_time - start_time;

  printf("convert image took: ");
  perf_print_value(convert_image_time);
  printf(" cycles\n");
  printf("convert filter took: ");
  perf_print_value(convert_filter_time);
  printf(" cycles\n");
  // evaluation correctness
  // int8_t reference_output[M_max][N_max];
  // for (int idx = 0; idx < M; ++idx) {
  //   for(int out_channel = 0; out_channel < N;++out_channel){
  //     int32_t acc = 0;
  //     for(int kdx = 0;kdx < K;++kdx){
  //       acc += (im2col[kdx][idx] + input_offset) * kernel[kdx][out_channel];
  //     }
  //     if (bias_data) {
  //       acc += bias_data[out_channel];
  //     }
  //     acc = MultiplyByQuantizedMultiplier(
  //         acc, output_multiplier[out_channel], output_shift[out_channel]);
  //     acc += output_offset;
  //     acc = std::max(acc, output_activation_min);
  //     acc = std::min(acc, output_activation_max);
  //     reference_output[idx][out_channel] = static_cast<int8_t>(acc);
  //     // output_data[Offset(output_shape, 0, idx / output_width, idx % output_width, out_channel)] = reference_output[idx][out_channel];
  //     //  output_data[Offset(output_shape, 0, idx / output_width, idx % output_width, out_channel)] = static_cast<int8_t>(acc);

  //   }
  // }

  // cal part
  int M_tile_factor;
  // L2-8
  if(K == 1750)M_tile_factor = 1; 
  // L9
  else if(K == 8000)M_tile_factor = 5;
  //L1,L10,L11
  else M_tile_factor = 2;
  printf("in this layer:\n");
  printf("M = %d, N = %d, K = %d\n", M, N, K);
  printf("tile M factor = %d\n", M_tile_factor);
  cfu_op0(/* funct7= */ 4, /* in0= */N, /* in1= */ input_offset);
  int M_start_idx = 0;
  int error_count = 0;
  for(int idx = 0;idx < M_tile_factor;idx++){
    int M_tile;
    if(M_tile_factor == 1)M_tile = M;
    else if(M_tile_factor == 5) M_tile = idx == 4 ? 20 : 32;
    else M_tile = idx == 0 ? 76 : 72;
    cfu_op0(/* funct7= */ 3, /* in0= */M_tile, /* in1= */ cast32_K);
    start_time = perf_get_mcycle64();
    for(int i = M_start_idx;i < M_start_idx + M_tile;i++){
      for(int j = 0;j < cast32_K;j+=32){
        uint32_t img =  *reinterpret_cast<uint32_t*>(&im2col[i][j]);
        uint32_t img2 =  *reinterpret_cast<uint32_t*>(&im2col[i][j+4]);
        cfu_op0(/* funct7= */ 0, /* in0= */ img, /* in1= */ img2);
        img =  *reinterpret_cast<uint32_t*>(&im2col[i][j+8]);
        img2 =  *reinterpret_cast<uint32_t*>(&im2col[i][j+12]);
        cfu_op0(/* funct7= */ 0, /* in0= */ img, /* in1= */ img2);
        img =  *reinterpret_cast<uint32_t*>(&im2col[i][j+16]);
        img2 =  *reinterpret_cast<uint32_t*>(&im2col[i][j+20]);
        cfu_op0(/* funct7= */ 0, /* in0= */ img, /* in1= */ img2);
        img =  *reinterpret_cast<uint32_t*>(&im2col[i][j+24]);
        img2 =  *reinterpret_cast<uint32_t*>(&im2col[i][j+28]);
        cfu_op0(/* funct7= */ 0, /* in0= */ img, /* in1= */ img2);
      }
    }
    end_time = perf_get_mcycle64();
    image_load_time += end_time - start_time;
    for(int ndx = 0;ndx < N;ndx++){
      start_time = perf_get_mcycle64();
      const int8_t* channel_ptr = kernel + (ndx * cast32_K);
      for(int i = 0;i < cast32_K;i+=32){
        uint32_t filter = *reinterpret_cast<uint32_t*>(&channel_ptr[i]);
        uint32_t filter2 = *reinterpret_cast<uint32_t*>(&channel_ptr[i+4]);
        cfu_op0(/* funct7= */ 1, /* in0= */ filter, /* in1= */ filter2);
        filter = *reinterpret_cast<uint32_t*>(&channel_ptr[i+8]);
        filter2 = *reinterpret_cast<uint32_t*>(&channel_ptr[i+12]);
        cfu_op0(/* funct7= */ 1, /* in0= */ filter, /* in1= */ filter2);
        filter = *reinterpret_cast<uint32_t*>(&channel_ptr[i+16]);
        filter2 = *reinterpret_cast<uint32_t*>(&channel_ptr[i+20]);
        cfu_op0(/* funct7= */ 1, /* in0= */ filter, /* in1= */ filter2);
        filter = *reinterpret_cast<uint32_t*>(&channel_ptr[i+24]);
        filter2 = *reinterpret_cast<uint32_t*>(&channel_ptr[i+28]);
        cfu_op0(/* funct7= */ 1, /* in0= */ filter, /* in1= */ filter2);
      }
      end_time = perf_get_mcycle64();
      filter_load_time += end_time - start_time;
      // get output
      start_time = perf_get_mcycle64();
      int8_t* target_ptr = output_data + (M_start_idx * N) + ndx;
      for(int i = M_start_idx;i < M_start_idx + M_tile;i++){
        int32_t res = cfu_op0(/* funct7= */ 2, /* in0= */ 0, /* in1= */ 0);
        if(bias_data){
          res += bias_data[ndx];
        }
        res = MultiplyByQuantizedMultiplier(
            res, output_multiplier[ndx], output_shift[ndx]);
        res += output_offset;
        res = std::max(res, output_activation_min);
        res = std::min(res, output_activation_max);
        // output_data[Offset(output_shape, 0, i / output_width, i % output_width, ndx)] = static_cast<int8_t>(res);
        *target_ptr = static_cast<int8_t>(res);
        target_ptr += N;
        // return ((i0 * dims_data[1] + i1) * dims_data[2] + i2) * dims_data[3] + i3;
      }
      end_time = perf_get_mcycle64();
      compute_and_out_time += end_time - start_time;
    }
    M_start_idx += M_tile;  
  }
  
  if(error_count == 0){
    printf("no error happened!\n");
  } else {
    printf("total error count is %d\n", error_count);
  }
  uint64_t total_end_time = perf_get_mcycle64();
  printf("filter load took: ");
  perf_print_value(filter_load_time);
  printf(" cycles\n");
  printf("image load took: ");
  perf_print_value(image_load_time);
  printf(" cycles\n");
  printf("compute and output took: ");
  perf_print_value(compute_and_out_time);
  printf(" cycles\n");
  perf_disable_counter(6);
  printf("total convolution took: ");
  perf_print_value(total_end_time - total_start_time);
  printf(" cycles\n\n");
  perf_disable_counter(6);
}

inline void ConvPerChannelWithPackedInt4Weights(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int8_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_input, int8_t* unpacked_filter_data,
    const RuntimeShape& bias_shape, const int32_t* bias_data,
    const RuntimeShape& output_shape, int8_t* output_data) {
  TFLITE_DCHECK(unpacked_filter_data != nullptr);
  tflite::tensor_utils::UnpackDenseInt4IntoInt8(
      filter_input, filter_shape.FlatSize(), unpacked_filter_data);
  ConvPerChannel(params, output_multiplier, output_shift, input_shape,
                 input_data, filter_shape, unpacked_filter_data, bias_shape,
                 bias_data, output_shape, output_data);
}

// Fixed-point per-channel-quantization convolution reference kernel.
// 16-bit data and 8-bit filter
template <typename AccumScalar>
inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int16_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const AccumScalar* bias_data, const RuntimeShape& output_shape,
    int16_t* output_data) {
  // Get parameters.
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;

  // Set min and max value of the output.
  const int32_t output_activation_min = params.quantized_activation_min;
  const int32_t output_activation_max = params.quantized_activation_max;

  // Consistency check.
  TFLITE_DCHECK_LE(output_activation_min, output_activation_max);
  TFLITE_DCHECK_EQ(input_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(filter_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(output_shape.DimensionsCount(), 4);
  const int batches = MatchingDim(input_shape, 0, output_shape, 0);
  const int input_depth = input_shape.Dims(3);
  const int output_depth = MatchingDim(filter_shape, 0, output_shape, 3);
  if (bias_data) {
    TFLITE_DCHECK_EQ(bias_shape.FlatSize(), output_depth);
  }

  // Check dimensions of the tensors.
  const int input_height = input_shape.Dims(1);
  const int input_width = input_shape.Dims(2);
  const int filter_height = filter_shape.Dims(1);
  const int filter_width = filter_shape.Dims(2);
  const int filter_input_depth = filter_shape.Dims(3);
  const int groups = input_depth / filter_input_depth;
  TFLITE_DCHECK_EQ(input_depth % filter_input_depth, 0);
  const int filters_per_group = output_depth / groups;
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);
  for (int batch = 0; batch < batches; ++batch) {
    for (int out_y = 0; out_y < output_height; ++out_y) {
      const int in_y_origin = (out_y * stride_height) - pad_height;
      for (int out_x = 0; out_x < output_width; ++out_x) {
        const int in_x_origin = (out_x * stride_width) - pad_width;
        for (int out_channel = 0; out_channel < output_depth; ++out_channel) {
          auto group = out_channel / filters_per_group;
          AccumScalar acc = 0;
          for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
            const int in_y = in_y_origin + dilation_height_factor * filter_y;
            for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
              const int in_x = in_x_origin + dilation_width_factor * filter_x;

              // Zero padding by omitting the areas outside the image.
              const bool is_point_inside_image =
                  (in_x >= 0) && (in_x < input_width) && (in_y >= 0) &&
                  (in_y < input_height);

              if (!is_point_inside_image) {
                continue;
              }

              for (int in_channel = 0; in_channel < filter_input_depth;
                   ++in_channel) {
                int32_t input_val =
                    input_data[Offset(input_shape, batch, in_y, in_x,
                                      in_channel + group * filter_input_depth)];
                int32_t filter_val = filter_data[Offset(
                    filter_shape, out_channel, filter_y, filter_x, in_channel)];
                // Accumulate with 64 bits accumulator.
                // int64_t += int8_t * int16_t so the highest value we can
                // get from each accumulation is [-127, 127] * ([-32768,
                // 32767] -
                // [-32768, 32767]), which is [-8322945, 8322945].
                // log2(8322945) = 22.99.
                acc += filter_val * input_val;
              }
            }
          }
          if (bias_data) {
            acc += bias_data[out_channel];
          }
          int32_t scaled_acc = MultiplyByQuantizedMultiplier(
              acc, output_multiplier[out_channel], output_shift[out_channel]);
          scaled_acc = std::max(scaled_acc, output_activation_min);
          scaled_acc = std::min(scaled_acc, output_activation_max);
          output_data[Offset(output_shape, batch, out_y, out_x, out_channel)] =
              static_cast<int16_t>(scaled_acc);
        }
      }
    }
  }
}

}  // namespace reference_integer_ops
}  // namespace tflite

#endif  // TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_
