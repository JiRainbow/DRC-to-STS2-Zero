"""Extract character skeletons from Dragon Raja (Zulong) UE4 assets.

Reads <name>-data.uasset/.uexp pairs (UE4 package magic 0x9E2A83C1), locates
skeleton blocks via the 0xFFFFFFFF marker heuristic (as in Bigchillghost's
Noesis script), and exports per character:
  - <name>.json : raw UE4 bind pose (cm, +Z up, local transforms)
  - <name>.glb  : glTF 2.0 skeleton-only (meters, +Y up)
plus a per-character zip.
"""
import json
import math
import re
import struct
import sys
import zipfile
from pathlib import Path

UE_MAGIC = 0x9E2A83C1
MAX_BONES = 0x200
SAFE_NAME_RE = re.compile(r'^[A-Za-z0-9_\- .]+$')
# basis change UE4 (+Z up, left-handed) -> glTF (+Y up, right-handed)
BASIS = (
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    (0.0, -1.0, 0.0),
)
M_TO_CM = 100.0


def u32(buf, off):
    return struct.unpack_from('<I', buf, off)[0]


def i32(buf, off):
    return struct.unpack_from('<i', buf, off)[0]


def parse_uasset(ua):
    """Follow Bigchillghost's header walk: returns (src_mode, strings)."""
    if len(ua) < 0x80 or u32(ua, 0) != UE_MAGIC:
        raise ValueError("not a UE4 package (magic)")
    p = 0x18
    srch = i32(ua, p)
    ln = i32(ua, p + 4)
    p += 8 + ln + 4
    string_num = i32(ua, p)
    string_buf = i32(ua, p + 4)
    end_magic = i32(ua, p + 8 + 0x78)
    src_mode = 1 if len(ua) < end_magic else 0
    if not (0 <= string_num < 0x10000) or not (0 <= string_buf < len(ua)):
        raise ValueError("bad name table header")
    strings = []
    q = string_buf
    for _ in range(string_num):
        slen = i32(ua, q)
        if slen < 0 or q + 4 + slen > len(ua):
            raise ValueError("bad string entry")
        strings.append(ua[q+4:q+4+slen].decode('utf-8', 'replace'))
        q += 4 + slen + 4
    return src_mode, srch, strings


def parse_bones(buf, off, strings):
    """Try to parse a skeleton header at off; returns (bones, end) or None."""
    cnt = u32(buf, off)
    if cnt == 0 or cnt >= MAX_BONES or off + 4 + cnt * 0xC > len(buf):
        return None
    name_idx = []
    parents = []
    p = off + 4
    for _ in range(cnt):
        ni = u32(buf, p)
        par = i32(buf, p + 8)
        if ni >= len(strings) or par < -1 or par >= cnt:
            return None
        name_idx.append(ni)
        parents.append(par)
        p += 0xC
    p += 4  # repeated bone count before the transform array
    bones = []
    for i in range(cnt):
        qx, qy, qz, qw, px, py, pz, sx, sy, sz = struct.unpack_from('<10f', buf, p)
        vals = (qx, qy, qz, qw, px, py, pz, sx, sy, sz)
        if not all(math.isfinite(v) for v in vals):
            return None
        if max(abs(v) for v in vals) > 1e7:
            return None
        bones.append({
            'name': strings[name_idx[i]],
            'parent': parents[i],
            'rotation': [qx, qy, qz, qw],
            'position': [px, py, pz],
            'scale': [sx, sy, sz],
        })
        p += 0x28
    return bones, p + cnt * 0xC + 4


def find_skeletons(buf, srch, strings):
    """Scan for validated skeleton headers; dedupe identical bone sets."""
    found = []
    seen = set()
    pos = max(srch, 0)
    while True:
        idx = buf.find(b'\xFF\xFF\xFF\xFF', pos)
        if idx < 0:
            break
        off = idx - 0xC
        if off >= 0:
            parsed = parse_bones(buf, off, strings)
            if parsed:
                bones, _end = parsed
                key = (tuple(b['name'] for b in bones), tuple(b['parent'] for b in bones))
                if key not in seen:
                    seen.add(key)
                    found.append(bones)
                pos = idx + 4
                continue
        pos = idx + 4
    return found


# --- glTF conversion helpers -------------------------------------------------

def quat_to_mat(q):
    x, y, z, w = q
    return (
        (1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)),
        (2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)),
        (2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y)),
    )


def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def mat_to_quat(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w = 0.25 * s
        x = (m[2][1] - m[1][2]) / s
        y = (m[0][2] - m[2][0]) / s
        z = (m[1][0] - m[0][1]) / s
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        w = (m[2][1] - m[1][2]) / s
        x = 0.25 * s
        y = (m[0][1] + m[1][0]) / s
        z = (m[0][2] + m[2][0]) / s
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        w = (m[0][2] - m[2][0]) / s
        x = (m[0][1] + m[1][0]) / s
        y = 0.25 * s
        z = (m[1][2] + m[2][1]) / s
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        w = (m[1][0] - m[0][1]) / s
        x = (m[0][2] + m[2][0]) / s
        y = (m[1][2] + m[2][1]) / s
        z = 0.25 * s
    return (x, y, z, w)


def to_gltf(bone):
    """UE4 local transform -> glTF (+Y up, meters)."""
    r = quat_to_mat(bone['rotation'])
    r2 = mat_mul(BASIS, mat_mul(r, tuple(tuple(BASIS[j][i] for j in range(3)) for i in range(3))))
    q = mat_to_quat(r2)
    px, py, pz = bone['position']
    pos = [px / M_TO_CM, pz / M_TO_CM, -py / M_TO_CM]
    s = bone['scale']
    return q, pos, s


def build_glb(name, bones):
    nodes = []
    roots = []
    for i, b in enumerate(bones):
        q, pos, s = to_gltf(b)
        node = {'name': b['name'], 'rotation': list(q), 'translation': pos}
        if any(abs(v - 1.0) > 1e-6 for v in s):
            node['scale'] = list(s)
        nodes.append(node)
    for i, b in enumerate(bones):
        par = b['parent']
        if 0 <= par < len(bones):
            nodes[par].setdefault('children', []).append(i)
        else:
            roots.append(i)
    gltf = {
        'asset': {'version': '2.0', 'generator': 'az_skeleton_extract'},
        'scene': 0,
        'scenes': [{'nodes': roots}],
        'nodes': nodes,
    }
    blob = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    pad = (4 - len(blob) % 4) % 4
    blob += b' ' * pad
    total = 12 + 8 + len(blob)
    return (struct.pack('<III', 0x46546C67, 2, total)
            + struct.pack('<II', len(blob), 0x4E4F534A) + blob)


def safe_dest(out_dir, *parts):
    dest = out_dir.joinpath(*parts).resolve()
    if out_dir not in dest.parents and dest != out_dir:
        raise ValueError(f"escapes output dir: {parts}")
    return dest


def main(models_root, out_root):
    models_root = Path(models_root)
    out_dir = Path(out_root).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    pairs = sorted(models_root.rglob('*-data.uasset'))
    print(f"found {len(pairs)} -data.uasset files under {models_root}")
    summary = []
    for ua_path in pairs:
        stem = ua_path.name[:-len('-data.uasset')]
        try:
            src_mode, srch, strings = parse_uasset(ua_path.read_bytes())
            if src_mode:
                uexp_path = ua_path.with_name(ua_path.name[:-len('.uasset')] + '.uexp')
                buf = uexp_path.read_bytes()
            else:
                buf = ua_path.read_bytes()
            skeletons = find_skeletons(buf, srch if not src_mode else 0, strings)
            if not skeletons:
                summary.append((str(ua_path.relative_to(models_root)), 0, 'no skeleton'))
                continue
            char_dir = safe_dest(out_dir, stem)
            char_dir.mkdir(parents=True, exist_ok=True)
            written = []
            for si, bones in enumerate(skeletons):
                suffix = f'_{si}' if len(skeletons) > 1 else ''
                jpath = safe_dest(out_dir, stem, f'{stem}{suffix}.json')
                gpath = safe_dest(out_dir, stem, f'{stem}{suffix}.glb')
                jdata = {
                    'character': stem,
                    'source': str(ua_path.relative_to(models_root.parent)),
                    'units': 'raw UE4 bind pose: centimeters, +Z up, local transforms, quaternion (x,y,z,w)',
                    'bone_count': len(bones),
                    'bones': bones,
                }
                jpath.write_bytes(json.dumps(jdata, ensure_ascii=False, indent=1).encode('utf-8'))
                gpath.write_bytes(build_glb(stem, bones))
                written.append((jpath, gpath, len(bones)))
            zpath = safe_dest(out_dir, f'{stem}.zip')
            with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as zf:
                for jpath, gpath, _ in written:
                    zf.write(jpath, jpath.name)
                    zf.write(gpath, gpath.name)
            counts = '/'.join(str(c) for _, _, c in written)
            summary.append((str(ua_path.relative_to(models_root)), len(skeletons), f'{counts} bones -> {zpath.name}'))
        except Exception as e:
            summary.append((str(ua_path.relative_to(models_root)), 0, f'ERROR: {e}'))
    ok = [s for s in summary if s[1] > 0]
    bad = [s for s in summary if s[1] == 0]
    print(f"\n=== skeletons extracted: {len(ok)} characters, skipped {len(bad)}")
    for rel, n, info in ok:
        print(f"  OK  {rel}: {info}")
    for rel, n, info in bad:
        print(f"  --  {rel}: {info}")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
