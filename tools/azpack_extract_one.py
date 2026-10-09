"""Targeted extract from an AZPAK container (EF23CA4D) by entry-name filter.

Reuses azpack_extract's index walk + block decode; only writes entries whose
name contains one of the given substrings. Backslash in a filter matches the
archive's path separator literally.
"""
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import azpack_extract as AZ


def extract_matching(pkg_path, out_dir, substrings):
    base = Path(out_dir).resolve()
    data = Path(pkg_path).read_bytes()
    eof = len(data)
    assert data[:4] == b'\xEF\x23\xCA\x4D'
    idx_off = struct.unpack_from('<I', data, eof - 0x114)[0] ^ AZ.KEY
    count = struct.unpack_from('<I', data, eof - 0x08)[0]
    pos = idx_off
    entries = []
    for _ in range(count):
        zsize = struct.unpack_from('<I', data, pos)[0] ^ AZ.KEY
        blob = zlib.decompress(data[pos + 8:pos + 8 + zsize])
        pos += 8 + zsize
        name = blob[:0x100].split(b'\x00')[0].decode('utf-8', 'replace')
        f0, offset, f2, size, csize, f5 = struct.unpack_from('<6I', blob, 0x100)
        entries.append((name, offset, size, csize))
    print(f"{Path(pkg_path).name}: {count} entries")

    gap_dicts = AZ.load_gap_dicts(data, [(o, o + c) for _, o, _, c in entries])
    lows = [s.lower().replace('\\', '/') for s in substrings]
    hits = [(n.replace('\\', '/'), o, s, c) for n, o, s, c in entries
            if any(s in n.lower().replace('\\', '/') for s in lows)]
    print(f"matching {len(hits)}:")
    for name, _, _, _ in hits:
        print("  ", name)
    for name, offset, size, csize in hits:
        blob = data[offset:offset + csize]
        if csize == size:
            out = blob
        elif blob[:4] == AZ.BLOCK_MAGIC:
            out = AZ.decode_zstd_block(blob, size, gap_dicts)
        elif blob[:1] == b'\x78':
            out = zlib.decompress(blob)
        else:
            print(f"  SKIP {name}: unknown storage")
            continue
        rel = name.replace('\\', '/')
        parts = [p for p in rel.split('/') if p not in ('', '.')]
        dest = base.joinpath(*parts)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(out)
        print(f"  written {dest} ({len(out)} B)")


if __name__ == '__main__':
    extract_matching(sys.argv[1], sys.argv[2], sys.argv[3:])
