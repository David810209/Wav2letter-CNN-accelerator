python3 gen.py
iverilog -g2012 -o tb tb.sv cfu.v
vvp tb