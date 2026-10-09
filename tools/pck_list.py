import struct, sys, zlib

def list_pck(path):
    d = open(path, 'rb').read()
    magic = d[:4]
    assert magic == b'GDPC', f'not a pck: {magic}'
    ver = struct.unpack_from('<I', d, 4)[0]
    major, minor, patch = struct.unpack_from('<III', d, 8)
    off = 20
    pack_flags = 0
    file_base = 0
    if ver >= 2:
        pack_flags, file_base = struct.unpack_from('<IQ', d, off)
        off += 12
    count = struct.unpack_from('<I', d, off)[0]
    off += 4
    files = {}
    for _ in range(count):
        slen = struct.unpack_from('<I', d, off)[0]
        off += 4
        name = d[off:off + slen].decode('utf-8').rstrip('\0')
        off += slen
        foff, fsize = struct.unpack_from('<QQ', d, off)
        off += 16 + 16  # offset+size+md5
        flags = 0
        if ver >= 2:
            flags = struct.unpack_from('<I', d, off)[0]
            off += 4
        files[name] = (foff + (file_base if pack_flags & 2 else 0), fsize, flags)
    return files, d

if __name__ == '__main__':
    for p in sys.argv[1:]:
        try:
            files, d = list_pck(p)
            hits = [n for n in files if 'ling.json' in n or 'ling.atlas' in n]
            print(f'== {p}')
            print(f'   files={len(files)} ling.json/atlas entries: {len(hits)}')
            for h in sorted(hits):
                off, size, flags = files[h]
                print(f'   {h}  ({size} B)')
                if h.endswith('ling.json'):
                    blob = d[off:off + min(size, 4000000)]
                    if flags & 1:  # compressed
                        blob = zlib.decompress(blob, 15, 100000000)
                    try:
                        j = json.loads(blob)
                        a = j['animations'].get('cast')
                        if a:
                            m = [0]
                            def mt(o):
                                if isinstance(o, dict):
                                    for k, v in o.items():
                                        if k == 'time' and isinstance(v, (int, float)):
                                            m[0] = max(m[0], v)
                                        else:
                                            mt(v)
                                elif isinstance(o, list):
                                    for v in o:
                                        mt(v)
                            mt(a)
                            print(f'      -> cast duration: {m[0]:.6f}s')
                        else:
                            print('      -> (no cast animation)', list(j.get("animations", {}).keys())[:8])
                    except Exception as e:
                        print('      parse fail:', e)
        except Exception as e:
            print(f'== {p}: ERROR {e}')

import json
