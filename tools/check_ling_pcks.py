import struct, sys, json

def list_pck(path):
    """Parse the pck layout used by tools/pck_writer.py (PCK v3 style:
    GDPC | ver=3 | engine | flags=REL_FILEBASE | file_base=0x70 | dir_off | rsvd
    | blob... | directory)."""
    d = open(path, 'rb').read()
    assert d[:4] == b'GDPC', f'not a pck: {d[:4]}'
    ver, major, minor, patch = struct.unpack_from('<IIII', d, 4)
    flags, = struct.unpack_from('<I', d, 0x14)
    file_base, = struct.unpack_from('<q', d, 0x18)
    dir_off, = struct.unpack_from('<q', d, 0x20)
    p = dir_off
    count, = struct.unpack_from('<I', d, p)
    p += 4
    files = {}
    for _ in range(count):
        plen, = struct.unpack_from('<I', d, p)
        p += 4
        name = d[p:p + plen].rstrip(b'\0').decode('utf-8')
        p += plen
        foff, fsize = struct.unpack_from('<qq', d, p)
        p += 16 + 16  # offset + size + md5
        p += 4        # v3 flags field
        real = foff + file_base if flags & 2 else foff
        files[name] = (real, fsize)
    return files, d


def max_time(o, acc):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'time' and isinstance(v, (int, float)):
                acc[0] = max(acc[0], v)
            else:
                max_time(v, acc)
    elif isinstance(o, list):
        for v in o:
            max_time(v, acc)


MODS = r"D:/Program Files (x86)/Steam/steamapps/common/Slay the Spire 2/mods"
for name in ('LingChar/LingChar.pck', 'LingUrbanSkin/LingUrbanSkin.pck', 'LingSilentSkin/LingSilentSkin.pck'):
    p = f'{MODS}/{name}'
    try:
        files, d = list_pck(p)
    except Exception as e:
        print(name, 'ERROR', repr(e))
        continue
    hits = sorted(n for n in files if 'ling.json' in n or 'characters/silent' in n.lower())
    print(f'== {name}: {len(files)} files')
    for h in hits:
        off, size = files[h]
        print(f'   {h} ({size}B)')
        if h.endswith('ling.json'):
            blob = bytes(d[off:off + size])
            try:
                j = json.loads(blob)
                anims = list(j.get('animations', {}).keys())
                info = f'      anims({len(anims)})'
                a = j['animations'].get('cast')
                if a is not None:
                    acc = [0]
                    max_time(a, acc)
                    info += f' cast_dur={acc[0]:.6f}s'
                info += f' has_skill01_3={"skill01_3" in j.get("animations", {})}'
                print(info)
                print('      names:', anims)
            except Exception as e:
                print('      parse fail:', repr(e))
