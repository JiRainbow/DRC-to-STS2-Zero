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
print('entries:', len(names))
BS = chr(92)
for pat in ['partner', 'pian', 'kizuna', 'head' + BS + 'ling', 'head' + BS + 'z', 'card_long']:
    hits = [n for n in names if pat.lower() in n.lower()]
    print(f'== {pat}: {len(hits)}')
    for h in hits[:14]:
        print('  ', h)
