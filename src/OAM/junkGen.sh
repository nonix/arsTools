#!/usr/bin/bash
# Generate CMOD look alike objects
for n in $(seq 1 100);do dd if=/dev/urandom bs=32K iflag=count_bytes count=$RANDOM of=${n}GAAA; done
