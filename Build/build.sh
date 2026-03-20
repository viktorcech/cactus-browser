#!/bin/bash
# Build script for VBXE Web Browser
# Assembler: MADS (Mad Assembler)

cd "$(dirname "$0")/.."

mkdir -p bin

echo "Assembling VBXE Web Browser..."
./mads.exe src/browser.asm -o:bin/browser.xex -l:bin/browser.lab -t:bin/browser.lst

if [ $? -eq 0 ]; then
    echo "Build successful: bin/browser.xex"
    ls -la bin/browser.xex
else
    echo "Build FAILED!"
    exit 1
fi
