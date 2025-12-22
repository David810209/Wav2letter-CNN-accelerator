python3 gen.py
cp ../cfu.v .
cp ../global_buffer_bram.v .
cp ../VPU.v .
iverilog -g2012 -o tb tb.sv cfu.v 
vvp tb