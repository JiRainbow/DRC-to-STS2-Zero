"""Walk AZPAK container indexes and filter entry names by substring."""
import struct
import sys
import zlib

sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parent))
import azpack_extract as AZ


def walk(pkg):
    data = open(pkg, 'rb').read()
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
    return names


if __name__ == '__main__':
    import os
    base = '../unpacked/apk/assets/res_base/package'
    pats = [s.lower() for s in sys.argv[2:]] or ['ghost', 'jingtong']
    for pkg in sorted(os.listdir(base)):
        if not pkg.endswith('.png'):
            continue
        p = os.path.join(base, pkg)
        try:
            names = walk(p)
        except Exception:
            continue
        hits = [n for n in names if any(x in n.lower() for x in pats)]
        if hits:
            print(f'== {pkg}: {len(hits)}')
            for h in hits[:15]:
                print('  ', h)
