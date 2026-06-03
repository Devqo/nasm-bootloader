#!/bin/bash
mkdir -p build

nasm -f bin src/boot.asm -o build/boot.bin

if [ $? -eq 0 ]; then
    echo "Starting QEMU..."
    qemu-system-x86_64 -drive format=raw,file=build/boot.bin
else
    echo "Compilation error."
fi
