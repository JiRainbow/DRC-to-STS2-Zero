import struct, zlib, os, sys, re, bisect
from pathlib import Path
import zstandard as zstd_mod

KEY = 0x62A4F9E1
DCTX = zstd_mod.ZstdDecompressor()

# archive entry names may only contain these safe characters
SAFE_NAME_RE = re.compile(r'^[A-Za-z0-9_\- .\\/]+$')

BLOCK_MAGIC = b'\x4D\x25\xED\xBC'
DICT_MAGIC = b'\x37\xa4\x30\xec'


def frame_dict_id(buf, off=0):
    """Dictionary ID declared by the zstd frame at buf[off] (0 if none)."""
    fhd = buf[off + 4]
    df = fhd & 3
    if df == 0:
        return 0
    ss = (fhd >> 5) & 1
    dsz = {1: 1, 2: 2, 3: 4}[df]
    o = off + 5 + (0 if ss else 1)
    return int.from_bytes(buf[o:o+dsz], 'little')


def load_gap_dicts(data, entry_spans):
    """Free-standing zstd dictionaries stored outside entry blocks."""
    spans = sorted(entry_spans)
    starts = [s for s, _ in spans]
    dicts = {}
    i = data.find(DICT_MAGIC)
    while i >= 0:
        k = bisect.bisect_right(starts, i) - 1
        inside = k >= 0 and spans[k][0] <= i < spans[k][1]
        if not inside:
            did = struct.unpack_from('<I', data, i+4)[0]
            if did and did not in dicts:
                nxt = min((s for s in starts if s > i), default=len(data))
                dicts[did] = data[i:nxt]
        i = data.find(DICT_MAGIC, i + 1)
    return dicts


def find_table_split(buf, start):
    """Find n where start + 4n + sum(u32[start:start+4n]) == len(buf)."""
    total = len(buf)
    s = 0
    n = 0
    while start + 4 * n <= total:
        if n > 0 and start + 4 * n + s == total:
            return n
        if start + 4 * n + 4 > total:
            break
        s += struct.unpack_from('<I', buf, start + 4 * n)[0]
        n += 1
        if s > total:
            break
    return None


def decode_zstd_block(blob, expect_size, gap_dicts=None):
    """Decode a 0xBCED254D block: magic(4) codec u16(2) size(4) capA(4) capB(4).
    capB==0: chunk-size table (n x u32) at 18 (n found by self-consistent split),
    then n zstd frames back to back.
    capB>0: u32@18 = size of frame0 at 22, whose DECOMPRESSED output is the
    zstd dictionary (capB bytes); then chunk-size table, then dict-compressed frames.
    Frames declaring an external dict ID fall back to gap_dicts lookup."""
    magic, codec, bsize, capA, capB = struct.unpack_from('<IHIII', blob, 0)
    if blob[:4] != BLOCK_MAGIC:
        raise ValueError(f"bad block magic {magic:#x}")
    if bsize != expect_size:
        raise ValueError(f"block size {bsize:#x} != entry size {expect_size:#x}")
    dctx = DCTX
    if capB:
        csize0 = struct.unpack_from('<I', blob, 18)[0]
        dict_bytes = DCTX.decompressobj().decompress(blob[22:22+csize0])
        if len(dict_bytes) != capB:
            raise ValueError(f"dict frame out {len(dict_bytes):#x} != capB {capB:#x}")
        if dict_bytes[:4] != DICT_MAGIC:
            raise ValueError("first frame is not a zstd dictionary")
        dctx = zstd_mod.ZstdDecompressor(dict_data=zstd_mod.ZstdCompressionDict(dict_bytes))
        tbl_at = 22 + csize0
    else:
        tbl_at = 18
    n = find_table_split(blob, tbl_at)
    if n is None:
        raise ValueError("no consistent chunk table")
    frames = struct.unpack_from(f'<{n}I', blob, tbl_at)
    pos = tbl_at + 4 * n
    out = bytearray()
    dict_dctxs = {}
    for fsize in frames:
        frame = blob[pos:pos+fsize]
        if frame[:4] == b'\x28\xb5\x2f\xfd' or frame[:1] == b'\x78':
            try:
                out += dctx.decompressobj().decompress(frame)
            except zstd_mod.ZstdError:
                did = frame_dict_id(frame)
                if gap_dicts and did in gap_dicts:
                    if did not in dict_dctxs:
                        dict_dctxs[did] = zstd_mod.ZstdDecompressor(
                            dict_data=zstd_mod.ZstdCompressionDict(gap_dicts[did]))
                    out += dict_dctxs[did].decompressobj().decompress(frame)
                else:
                    raise
        else:
            out += frame                  # stored chunk (raw tail)
        pos += fsize
    if pos != len(blob):
        raise ValueError(f"block consumed {pos:#x} != {len(blob):#x}")
    if len(out) != bsize:
        raise ValueError(f"decompressed {len(out)} != {bsize}")
    return bytes(out)


def extract(pkg_path, out_dir, limit=None):
    base = Path(out_dir).resolve()
    data = Path(pkg_path).read_bytes()
    eof = len(data)
    assert data[:4] == b'\xEF\x23\xCA\x4D'
    assert data[12:16] == b'\xB7\x89\xA0\x56', data[12:16].hex()
    idx_off = struct.unpack_from('<I', data, eof-0x114)[0] ^ KEY
    count = struct.unpack_from('<I', data, eof-0x08)[0]
    print(f"{Path(pkg_path).name}: eof={eof:#x} idx={idx_off:#x} count={count}")

    pos = idx_off
    entries = []
    for i in range(count):
        zsize = struct.unpack_from('<I', data, pos)[0] ^ KEY
        blob = zlib.decompress(data[pos+8:pos+8+zsize])
        assert len(blob) == 0x118, (i, len(blob))
        pos += 8 + zsize
        name = blob[:0x100].split(b'\x00')[0].decode('utf-8', 'replace')
        f0, offset, f2, size, csize, f5 = struct.unpack_from('<6I', blob, 0x100)
        entries.append((name, offset, size, csize))
    print(f"  index walked to {pos:#x} (gap to banner: {eof-0x114-pos})")

    gap_dicts = load_gap_dicts(data, [(o, o + c) for _, o, _, c in entries])
    base.mkdir(parents=True, exist_ok=True)
    extracted, failed = 0, 0
    for name, offset, size, csize in entries[:limit]:
        try:
            # sanitize the archive-derived name before touching the filesystem
            rel = name.replace('\\', '/')
            if not rel or not SAFE_NAME_RE.fullmatch(rel):
                raise ValueError(f"unsafe chars in entry name {name!r}")
            parts = [p for p in rel.split('/') if p not in ('', '.')]
            if not parts or ':' in rel or rel.startswith('/') or os.pardir in parts:
                raise ValueError(f"traversal in entry name {name!r}")
            dest = base.joinpath(*parts).resolve()
            if base not in dest.parents:
                raise ValueError(f"escapes output dir: {name!r}")

            blob = data[offset:offset+csize]
            if csize == size:
                out = blob                      # stored, no block header
            elif blob[:4] == BLOCK_MAGIC:
                out = decode_zstd_block(blob, size, gap_dicts)
            elif blob[:1] == b'\x78':
                out = zlib.decompress(blob)
            else:
                raise ValueError(f"unknown storage, first bytes {blob[:8].hex()}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(out)
            extracted += 1
        except Exception as e:
            failed += 1
            if failed <= 3:
                print(f"  FAIL {name!r}: {e}")
    print(f"  extracted={extracted} failed={failed}")
    return entries


if __name__ == '__main__':
    pkg, out = sys.argv[1], sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else None
    extract(pkg, out, limit)
