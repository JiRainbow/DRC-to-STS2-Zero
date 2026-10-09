"""Extract Spine 2D skeletons from Dragon Raja (Zulong) UE4 assets.

The game's characters/monsters are Spine skeletons (SpineSkeletonDataAsset):
the paired <name>-data.uexp embeds a Spine 4.1 binary .skel (big-endian
floats/ints, 7-bit varints, counted strings), and <name>-atlas.uexp embeds
the plaintext .atlas text. This tool extracts both, parses the bone/slot
hierarchy into readable JSON, and packages everything per character.

Output per character (under out_root):
  <stem>/<stem>.skel          raw Spine binary skeleton
  <stem>/<stem>.atlas         texture atlas description
  <stem>/<stem>_bones.json    parsed skeleton (bones + slots + meta)
  <stem>.zip                  zip of the above
"""
import json
import math
import re
import struct
import sys
import zipfile
from pathlib import Path

MAX_STRINGS = 20000
MAX_BONES = 512
MAX_SLOTS = 512
VERSION_RE = re.compile(r'^\d+\.\d+\.\d+.*$')
SAFE_STEM_RE = re.compile(r'^[A-Za-z0-9_\-]+$')
BLEND_MODES = ['normal', 'additive', 'multiply', 'screen']
TRANSFORM_MODES = ['normal', 'onlyTranslation', 'noRotationOrReflection', 'noScale', 'noScaleOrReflection']


def varint(buf, p):
    v = 0
    shift = 0
    while True:
        b = buf[p]
        p += 1
        v |= (b & 0x7F) << shift
        if not (b & 0x80):
            return v, p
        shift += 7
        if shift > 35:
            raise ValueError("varint too long")


def read_str(buf, p):
    """Spine 4.1 readString: varint byteCount; 0=None, 1=''; else byteCount-1 bytes."""
    cc, p = varint(buf, p)
    if cc == 0:
        return None, p
    if cc == 1:
        return '', p
    n = cc - 1
    raw = buf[p:p+n]
    if len(raw) < n:
        raise ValueError("string overruns buffer")
    p += n
    return raw.decode('utf-8'), p


def f32be(buf, p):
    return struct.unpack_from('>f', buf, p)[0]


def i32be(buf, p):
    return struct.unpack_from('>i', buf, p)[0]


def sane_float(v, lo=-1e7, hi=1e7):
    return math.isfinite(v) and lo <= v <= hi


def try_parse_spine(buf, start):
    """Attempt a full header+bones+slots parse at `start`; raises on any inconsistency."""
    p = start + 8  # hash (8 bytes, not interpreted)
    cc, p = varint(buf, p)
    if not 2 <= cc <= 32:
        raise ValueError("bad version length")
    ver = buf[p:p+cc-1].decode('utf-8')
    p += cc - 1
    if not VERSION_RE.match(ver):
        raise ValueError(f"bad version {ver!r}")
    x, y, w, h = struct.unpack_from('>4f', buf, p)
    p += 16
    if not all(sane_float(v) for v in (x, y, w, h)) or not (0 <= w <= 100000 and 0 <= h <= 100000):
        raise ValueError("bad canvas floats")
    nonessential = buf[p]
    p += 1
    info = {'spine_version': ver, 'canvas': {'x': x, 'y': y, 'width': w, 'height': h}}
    if nonessential > 1:
        raise ValueError("bad nonessential flag")
    if nonessential:
        fps = f32be(buf, p)
        p += 4
        if not sane_float(fps, 1, 240):
            raise ValueError("bad fps")
        img, p = read_str(buf, p)
        aud, p = read_str(buf, p)
        if img is None or len(img) > 512 or (aud is not None and len(aud) > 512):
            raise ValueError("bad path strings")
        info['fps'] = fps
        info['images_path'] = img
        info['audio_path'] = aud
    nstr, p = varint(buf, p)
    if nstr > MAX_STRINGS:
        raise ValueError("strings table too large")
    strings = []
    for _ in range(nstr):
        s, p = read_str(buf, p)
        strings.append(s)
    info['strings_count'] = nstr

    nbones, p = varint(buf, p)
    if not 0 < nbones <= MAX_BONES:
        raise ValueError("bad bone count")
    bones = []
    for i in range(nbones):
        name, p = read_str(buf, p)
        if not name or len(name) > 128:
            raise ValueError("bad bone name")
        bone = {'name': name}
        if i > 0:
            par, p = varint(buf, p)
            if par >= i:
                raise ValueError("bad bone parent")
            bone['parent'] = par
        else:
            bone['parent'] = -1
        vals = struct.unpack_from('>8f', buf, p)
        p += 32
        if not all(sane_float(v) for v in vals):
            raise ValueError("bad bone floats")
        bone.update(zip(('rotation', 'x', 'y', 'scaleX', 'scaleY', 'shearX', 'shearY', 'length'), vals))
        tm, p = varint(buf, p)
        if tm >= len(TRANSFORM_MODES):
            raise ValueError("bad transform mode")
        bone['transform_mode'] = TRANSFORM_MODES[tm]
        skin_required = buf[p]
        p += 1
        if skin_required > 1:
            raise ValueError("bad skinRequired")
        bone['skin_required'] = bool(skin_required)
        if nonessential:
            bone['color'] = struct.unpack_from('>I', buf, p)[0]
            p += 4
        bones.append(bone)
    info['bones'] = bones

    nslots, p = varint(buf, p)
    if nslots > MAX_SLOTS:
        raise ValueError("bad slot count")
    slots = []
    for _ in range(nslots):
        name, p = read_str(buf, p)
        if not name or len(name) > 128:
            raise ValueError("bad slot name")
        bi, p = varint(buf, p)
        if bi >= nbones:
            raise ValueError("bad slot bone")
        color = i32be(buf, p)
        p += 4
        dark = i32be(buf, p)
        p += 4
        att_ref, p = varint(buf, p)
        att = None if att_ref == 0 else strings[att_ref - 1]
        blend, p = varint(buf, p)
        if blend >= len(BLEND_MODES):
            raise ValueError("bad blend mode")
        slots.append({'name': name, 'bone': bones[bi]['name'], 'attachment': att,
                      'blend': BLEND_MODES[blend], 'color': color & 0xFFFFFFFF,
                      'dark_color': None if dark == -1 else dark & 0xFFFFFFFF})
    info['slots'] = slots
    info['parse_end'] = p
    return info


def locate_spine(uexp):
    """Find and validate the embedded Spine skeleton; returns (skel_bytes, info)."""
    for start in range(0x00, 0x100):
        try:
            info = try_parse_spine(uexp, start)
        except (ValueError, IndexError, struct.error, UnicodeDecodeError):
            continue
        cnt = struct.unpack_from('<I', uexp, start - 4)[0] if start >= 4 else 0
        if 0 < cnt <= len(uexp) - start and info['parse_end'] <= start + cnt:
            return uexp[start:start+cnt], info
        return uexp[start:], info  # no sane length prefix; take the rest
    raise ValueError("no spine skeleton found")


def locate_atlas(uexp):
    """Extract the plaintext .atlas text block embedded in the atlas .uexp."""
    m = re.search(rb'[\x20-\x7e][\x20-\x7e\-_.]{0,120}\.png\r?\nsize:', uexp)
    if not m:
        raise ValueError("no atlas text found")
    # backtrack to the start of the page-name line
    s = m.start()
    while s > 0 and 0x20 <= uexp[s-1] <= 0x7e:
        s -= 1
    end = uexp.find(b'\nsize:', m.start())
    while True:
        nxt = uexp.find(b'\nsize:', end + 1)
        if nxt < 0:
            break
        end = nxt
    end = uexp.find(b'\n', end + 1)
    if end < 0:
        end = len(uexp)
    text_len = end - s
    if s >= 4 and struct.unpack_from('<I', uexp, s - 4)[0] == text_len:
        end = s + text_len
    return uexp[s:end].decode('utf-8', 'replace')


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
    print(f"found {len(pairs)} -data.uasset files")
    ok, skipped = [], []
    for ua_path in pairs:
        stem = ua_path.name[:-len('-data.uasset')]
        if not SAFE_STEM_RE.fullmatch(stem):
            skipped.append((ua_path, 'unsafe name'))
            continue
        uexp_path = ua_path.with_name(ua_path.name[:-len('.uasset')] + '.uexp')
        if not uexp_path.exists():
            skipped.append((ua_path, 'no uexp'))
            continue
        try:
            uexp = uexp_path.read_bytes()
            skel, info = locate_spine(uexp)
        except Exception as e:
            skipped.append((ua_path, f'{type(e).__name__}: {e}'))
            continue
        char_dir = safe_dest(out_dir, stem)
        char_dir.mkdir(parents=True, exist_ok=True)
        skel_path = safe_dest(out_dir, stem, f'{stem}.skel')
        skel_path.write_bytes(skel)
        meta = {
            'character': stem,
            'source_uexp': str(uexp_path.relative_to(models_root.parent)),
            'skel_bytes': len(skel),
            'bone_count': len(info['bones']),
            'slot_count': len(info['slots']),
            'spine': {k: v for k, v in info.items() if k != 'parse_end'},
            'note': '.skel is the complete Spine binary (includes animations); use Spine viewers/runtimes with the .atlas and game textures',
        }
        jpath = safe_dest(out_dir, stem, f'{stem}_bones.json')
        jpath.write_bytes(json.dumps(meta, ensure_ascii=False, indent=1).encode('utf-8'))
        atlas_path = ua_path.with_name(ua_path.name.replace('-data.uasset', '-atlas.uexp'))
        if atlas_path.exists():
            try:
                atext = locate_atlas(atlas_path.read_bytes())
                safe_dest(out_dir, stem, f'{stem}.atlas').write_text(atext, encoding='utf-8', newline='')
            except Exception as e:
                meta['atlas_error'] = str(e)
                jpath.write_bytes(json.dumps(meta, ensure_ascii=False, indent=1).encode('utf-8'))
        zpath = safe_dest(out_dir, f'{stem}.zip')
        with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as zf:
            for f in char_dir.iterdir():
                zf.write(f, f.name)
        ok.append((stem, info['spine_version'], len(info['bones']), len(info['slots']),
                   f"{len(skel):#x}B -> {zpath.name}"))
    print(f"\n=== extracted {len(ok)} spine skeletons, skipped {len(skipped)}")
    for stem, ver, nb, ns, dst in ok:
        print(f"  OK  {stem}: spine {ver}, {nb} bones, {ns} slots, {dst}")
    for path, why in skipped:
        print(f"  --  {path.name}: {why}")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
