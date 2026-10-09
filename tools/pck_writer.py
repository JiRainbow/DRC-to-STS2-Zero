"""Build a Godot PCK v3 (as used by Slay the Spire 2) from a file list."""
import hashlib
import struct
from pathlib import Path


def build_pck(files, out_path, engine=(4, 5, 1)):
    """files: list of (pck_path, src_path). pck_path uses forward slashes,
    relative to res://."""
    entries = []
    for pck_path, src in files:
        data = Path(src).read_bytes()
        entries.append((pck_path, data))

    HEADER = 0x70
    blob = bytearray()
    offsets = []
    for pck_path, data in entries:
        offsets.append((pck_path, len(blob), len(data)))
        blob += data

    # directory
    dir_buf = bytearray()
    dir_buf += struct.pack('<I', len(entries))
    for (pck_path, off, size), (_, data) in zip(offsets, entries):
        pb = pck_path.encode('utf-8')
        pad = (-len(pb)) % 4
        pb += b'\x00' * pad
        dir_buf += struct.pack('<I', len(pb)) + pb
        dir_buf += struct.pack('<qq', off, size)
        # NOTE: 16-byte MD5 is mandated by the Godot PCK v3 container format
        # (per-entry integrity field), not a security choice.
        dir_buf += hashlib.md5(data).digest()
        dir_buf += struct.pack('<I', 0)          # v3 extra field

    out = bytearray()
    out += b'GDPC'
    out += struct.pack('<IIII', 3, engine[0], engine[1], engine[2])
    out += struct.pack('<I', 2)                   # flags: PACK_REL_FILEBASE
    out += struct.pack('<q', HEADER)              # file_base
    out += struct.pack('<q', HEADER + len(blob))  # dir offset (patched slot @0x20)
    out += struct.pack('<q', 0)                   # reserved
    assert len(out) == 0x30
    out += b'\x00' * (HEADER - len(out))
    out += blob
    out += dir_buf

    Path(out_path).write_bytes(bytes(out))
    return len(entries), len(out)
