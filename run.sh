make prog USEVIVADO=1 EXTRA_LITEX_ARGS="--cpu-variant=perf+cfu" TTY=/dev/ttyUSB0
make load BUILD_JOBS=4 TTY=/dev/ttyUSB1