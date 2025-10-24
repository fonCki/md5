#!/usr/bin/env python3
"""
pad_to_block.py

Pad an arbitrary binary file with 0x00 bytes until its length is a multiple
of 64 bytes (512 bits). Usage:
  python3 pad_to_block.py <file1> [file2 ...]
"""
import sys
from pathlib import Path

def pad_file(path: Path, block=64):
    data = path.read_bytes()
    rem = len(data) % block
    if rem == 0:
        print(f"{path}: already aligned ({len(data)} bytes)")
        return
    pad_len = (block - rem) % block
    if pad_len == 0:
        print(f"{path}: no padding needed")
        return
    path.write_bytes(data + b'\x00' * pad_len)
    print(f"{path}: padded {pad_len} bytes -> {len(data)+pad_len} bytes total")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 pad_to_block.py <file1> [file2 ...]")
        sys.exit(1)
    for arg in sys.argv[1:]:
        pad_file(Path(arg))

if __name__ == "__main__":
    main()
