# Wav2letter-CNN-Accelerator

This repository presents a convolutional neural network accelerator implemented on top of the CFU-Playground framework.  
The project is developed as the final project for the course **“Accelerator Architectures for Machine Learning”**, with a focus on efficient execution of CNN workloads.
  
## Setup

- First, obtain a Digilent Nexys4DDR or Arty A7-100T FPGA board, connect it to your computer, and install Vivado.

### 1.
in CFU-Playground/proj directory:

```bash
git clone https://github.com/David810209/Wav2letter-CNN-accelerator
cd Wav2letter-CNN-accelerator/src/wav2letter/model
wget https://github.com/ARM-software/ML-Zoo/raw/master/models/speech_recognition/wav2letter/tflite_pruned_int8/wav2letter_pruned_int8.tflite
chmod +x model_convert.sh
./model_convert.sh
cd ../../../
make prog USEVIVADO=1 EXTRA_LITEX_ARGS="--cpu-variant=perf+cfu" TTY=/dev/ttyUSB0
make load BUILD_JOBS=4 TTY=/dev/ttyUSB1
```

### 2.
reboot

### 3.
Close the litex-term terminal
### 4.

```bash
python3 eval.py --port /dev/ttyUSB1
```

## Selected Model

The target workload for this accelerator is a quantized version of the **Wav2Letter** speech recognition model:

- Model source:  
  https://github.com/ARM-software/ML-Zoo/raw/master/models/speech_recognition/wav2letter/tflite_pruned_int8/wav2letter_pruned_int8.tflite

- The model is:
  - The default implementation, provided by Arm, is quantized using the TensorFlow Model Optimization Toolkit.

- Architecture characteristics:
  - 11 large Conv2D layers
  - Intermediate Leaky ReLU activations

## Contributions

* This project is powered by [CFU-Playground](https://github.com/google/CFU-Playground)