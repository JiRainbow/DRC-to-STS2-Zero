"""List / extract Godot 4 PCK contents."""
import os
import struct
import sys
from pathlib import Path


def sanitize_rel(path):
    """Make an archive-provided res:// path safe to join under an extract dir."""
    rel = path.replace('res://', '').replace('\\', '/')
    parts = [p for p in rel.split('/') if p not in ('', '.')]
    if not parts or any(p == '..' or ':' in p for p in parts) or rel.startswith('/'):
        raise ValueError(f"unsafe entry path {path!r}")
    return Path(*parts)


def read_pck(path, extract_dir=None, only=None, stream=False):
    if stream:
        f = open(path, 'rb')
        head = f.read(64)
    else:
        data = Path(path).read_bytes()
        f = None
        head = data[:64]
    if head[:4] != b'GDPC':
        raise ValueError("not a Godot PCK (maybe embedded in exe)")
    ver = struct.unpack_from('<I', head, 4)[0]
    major, minor, patch = struct.unpack_from('<III', head, 8)
    print(f"{path}: pck v{ver} engine {major}.{minor}.{patch}")
    flags = struct.unpack_from('<I', head, 20)[0]
    file_base = struct.unpack_from('<q', head, 24)[0]
    p = 32
    dir_at = None
    if ver >= 3:
        dir_at = struct.unpack_from('<q', head, p)[0]
    elif ver == 2:
        # PCKPacker v2: fixed 0x60-byte header, directory immediately follows
        dir_at = 0x60
    else:
        dir_at = 32

    def rd(off, n):
        if f:
            f.seek(off)
            return f.read(n)
        return data[off:off+n]

    p = dir_at
    count = struct.unpack_from('<I', rd(p, 4), 0)[0]
    p += 4
    print(f"files: {count} flags={flags:#x} file_base={file_base:#x} dir_at={dir_at and hex(dir_at)}")
    entries = []
    for _ in range(count):
        slen = struct.unpack_from('<I', rd(p, 4), 0)[0]
        p += 4
        path = rd(p, slen).rstrip(b'\x00').decode('utf-8', 'replace')
        p += slen
        off, size = struct.unpack_from('<qq', rd(p, 16), 0)
        p += 16
        p += 16  # md5
        if ver >= 2:
            p += 4  # extra per-entry field (flags), present in v2 and v3
        entries.append((path, off, size))
    extract_root = Path(extract_dir).resolve() if extract_dir else None
    for path, off, size in entries:
        if only and only not in path:
            continue
        print(f"  {size:>10}  {path}")
        if extract_root:
            rel = sanitize_rel(path)
            dst = (extract_root / rel).resolve()
            if extract_root not in dst.parents:
                raise ValueError(f"escapes extract dir: {path}")
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(rd(file_base + off, size))
    return entries


if __name__ == '__main__':
    src = sys.argv[1]
    extract = sys.argv[2] if len(sys.argv) > 2 else None
    only = sys.argv[3] if len(sys.argv) > 3 else None
    read_pck(src, extract, only)
