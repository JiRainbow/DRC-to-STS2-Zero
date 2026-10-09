import struct
import zlib

import azpack_extract as AZ

data = open('../unpacked/apk/assets/res_base/package/ui.png', 'rb').read()
eof = len(data)
idx_off = struct.unpack_from('<I', data, eof - 0x114)[0] ^ AZ.KEY
count = struct.unpack_from('<I', data, eof - 0x08)[0]
pos = idx_off
names = []
for _ in range(count):
    zsize = struct.unpack_from('<I', data, pos)[0] ^ AZ.KEY
    blob = zlib.decompress(data[pos + 8:pos + 8 + zsize])
    pos += 8 + zsize
    names.append(blob[:0x100].split(b'\x00')[0].decode('utf-8', 'replace'))

BS = chr(92)
dirs = {}
for n in names:
    parts = n.lower().split(BS)
    if len(parts) > 1:
        dirs.setdefault(parts[0] + BS + parts[1], 0)
        dirs[parts[0] + BS + parts[1]] += 1
for d, c in sorted(dirs.items()):
    print(f'{c:4}  {d}')
