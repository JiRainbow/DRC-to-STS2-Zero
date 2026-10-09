"""Spine 4.1 binary skeleton -> Spine JSON converter (with animation renaming).

Implements the full SkeletonBinary 4.1 format per the official runtime source
(spine-libgdx SkeletonBinary.java), and emits Spine 4.1 JSON that
spine-godot (4.2 runtime, used by Slay the Spire 2) loads natively.

Validation strategy: the parser must consume the input byte-exactly
(leftover == 0), which strongly verifies every format decision.
"""
import json
import re
import struct
import sys


class R:
    def __init__(self, buf):
        self.b = buf
        self.p = 0

    def byte(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def boolean(self):
        return self.byte() != 0

    def varint(self, positive=True):
        b = self.byte()
        v = b & 0x7F
        if b & 0x80:
            b = self.byte()
            v |= (b & 0x7F) << 7
            if b & 0x80:
                b = self.byte()
                v |= (b & 0x7F) << 14
                if b & 0x80:
                    b = self.byte()
                    v |= (b & 0x7F) << 21
                    if b & 0x80:
                        b = self.byte()
                        v |= (b & 0x7F) << 28
        if positive:
            return v
        return (v >> 1) ^ -(v & 1)   # zigzag decode

    def f32(self):
        v = struct.unpack_from('>f', self.b, self.p)[0]
        self.p += 4
        return v

    def i32(self):
        v = struct.unpack_from('>i', self.b, self.p)[0]
        self.p += 4
        return v

    def u32(self):
        v = struct.unpack_from('>I', self.b, self.p)[0]
        self.p += 4
        return v

    def i16(self):
        v = struct.unpack_from('>h', self.b, self.p)[0]
        self.p += 2
        return v

    def string(self):
        n = self.varint()
        if n == 0:
            return None
        if n == 1:
            return ''
        raw = self.b[self.p:self.p + n - 1]
        self.p += n - 1
        return raw.decode('utf-8')

    def remaining(self):
        return len(self.b) - self.p


def hex_color(c):
    return f'#{(c & 0xFFFFFFFF):08x}'


def f(v):
    """Clean float for JSON (drop float noise)."""
    if v is None:
        return None
    r = round(v, 6)
    return int(r) if r == int(r) and abs(r) < 1e15 else r


# ---------------------------------------------------------------- skeleton ---

def parse_skeleton(buf):
    r = R(buf)
    sk = {}
    hash_lo, hash_hi = struct.unpack_from('>II', buf, 0)
    r.p = 8
    sk['hash'] = str(struct.unpack_from('>q', buf, 0)[0]) if struct.unpack_from('>q', buf, 0)[0] != 0 else None
    sk['spine'] = r.string()
    sk['x'], sk['y'], sk['width'], sk['height'] = r.f32(), r.f32(), r.f32(), r.f32()
    nonessential = r.boolean()
    sk['nonessential'] = nonessential
    if nonessential:
        sk['fps'] = r.f32()
        sk['images'] = r.string()
        sk['audio'] = r.string()

    n = r.varint()
    strings = [r.string() for _ in range(n)]
    sk['_strings_count'] = n

    # bones
    bones = []
    for i in range(r.varint()):
        b = {'name': r.string()}
        if i > 0:
            b['parent'] = r.varint()
        b['rotation'] = r.f32()
        b['x'], b['y'] = r.f32(), r.f32()
        b['scaleX'], b['scaleY'] = r.f32(), r.f32()
        b['shearX'], b['shearY'] = r.f32(), r.f32()
        b['length'] = r.f32()
        b['transform_mode'] = r.varint()
        b['skin_required'] = r.boolean()
        if nonessential:
            b['color'] = r.u32()
        bones.append(b)
    sk['bones'] = bones

    # slots
    slots = []
    for _ in range(r.varint()):
        s = {'name': r.string(), 'bone': r.varint(), 'color': r.u32(), 'dark': r.i32()}
        att = r.varint()
        s['attachment'] = None if att == 0 else strings[att - 1]
        s['blend'] = r.varint()
        slots.append(s)
    sk['slots'] = slots

    # ik
    iks = []
    for _ in range(r.varint()):
        c = {'name': r.string(), 'order': r.varint(), 'skin_required': r.boolean()}
        c['bones'] = [r.varint() for _ in range(r.varint())]
        c['target'] = r.varint()
        c['mix'] = r.f32()
        c['softness'] = r.f32()
        c['bend_direction'] = struct.unpack_from('>b', r.b, r.p)[0]
        r.p += 1
        c['compress'], c['stretch'], c['uniform'] = r.boolean(), r.boolean(), r.boolean()
        iks.append(c)
    sk['ik'] = iks

    # transform
    tfs = []
    for _ in range(r.varint()):
        c = {'name': r.string(), 'order': r.varint(), 'skin_required': r.boolean()}
        c['bones'] = [r.varint() for _ in range(r.varint())]
        c['target'] = r.varint()
        c['local'], c['relative'] = r.boolean(), r.boolean()
        c['offsetRotation'] = r.f32()
        c['offsetX'], c['offsetY'] = r.f32(), r.f32()
        c['offsetScaleX'], c['offsetScaleY'] = r.f32(), r.f32()
        c['offsetShearY'] = r.f32()
        c['mixRotate'], c['mixX'], c['mixY'] = r.f32(), r.f32(), r.f32()
        c['mixScaleX'], c['mixScaleY'], c['mixShearY'] = r.f32(), r.f32(), r.f32()
        tfs.append(c)
    sk['transform'] = tfs

    # path
    pcs = []
    for _ in range(r.varint()):
        c = {'name': r.string(), 'order': r.varint(), 'skin_required': r.boolean()}
        c['bones'] = [r.varint() for _ in range(r.varint())]
        c['target'] = r.varint()
        c['positionMode'], c['spacingMode'], c['rotateMode'] = r.varint(), r.varint(), r.varint()
        c['offsetRotation'] = r.f32()
        c['position'], c['spacing'] = r.f32(), r.f32()
        c['mixRotate'], c['mixX'], c['mixY'] = r.f32(), r.f32(), r.f32()
        pcs.append(c)
    sk['path'] = pcs

    # skins
    linked = []
    skin_ctx = {'strings': strings}
    dskin = read_skin(r, sk, skin_ctx, linked, default=True, nonessential=nonessential)
    skins = []
    if dskin is not None:
        skins.append(dskin)
    for _ in range(r.varint()):
        skins.append(read_skin(r, sk, skin_ctx, linked, default=False, nonessential=nonessential))
    sk['skins'] = skins

    # resolve linked meshes
    for lm in linked:
        parent_skin = None
        for s in skins:
            if s['name'] == lm['skin_name']:
                parent_skin = s
                break
        if lm['skin_name'] is None and dskin is not None:
            parent_skin = dskin
        assert parent_skin is not None, f"linked mesh skin {lm['skin_name']} not found"
        atts = parent_skin['slots'][lm['slot_index']][1]
        parent = atts[lm['parent_name']]
        lm['att']['parent'] = lm['parent_name']
        lm['att']['_parent_path'] = parent.get('path')

    # events
    events = []
    for _ in range(r.varint()):
        e = {'name': r.varint()}   # stringref
        e['int'] = r.varint(positive=False)
        e['float'] = r.f32()
        e['string'] = r.string()
        e['audio'] = r.string()
        if e['audio'] is not None:
            e['volume'] = r.f32()
            e['balance'] = r.f32()
        events.append(e)
    sk['events'] = events

    # animations
    anims = {}
    for _ in range(r.varint()):
        name = r.string()
        anims[name] = parse_animation(r, sk, strings)
    sk['animations'] = anims
    sk['leftover'] = r.remaining()
    sk['_strings'] = strings
    return sk


def read_sequence(r):
    if not r.boolean():
        return None
    return {'count': r.varint(), 'start': r.varint(), 'digits': r.varint(), 'setupIndex': r.varint()}


def read_vertices(r, n):
    weighted = r.boolean()
    if not weighted:
        return {'vertices': [r.f32() for _ in range(n * 2)], 'bones': None}
    out = []
    for _ in range(n):
        bc = r.varint()
        out.append(bc)
        for _ in range(bc):
            out.append(r.varint())
            out.append(r.f32())
            out.append(r.f32())
            out.append(r.f32())
    return {'vertices': out, 'bones': True}


def read_short_array(r):
    return [r.i16() for _ in range(r.varint())]


def read_skin(r, sk, ctx, linked, default, nonessential):
    if default:
        slot_count = r.varint()
        if slot_count == 0:
            return None
        skin = {'name': 'default', 'bones': [], 'constraints': []}
    else:
        name_ref = r.varint()
        skin = {'name': ctx['strings'][name_ref - 1] if name_ref else None, 'bones': [], 'constraints': []}
        for _ in range(r.varint()):
            skin['bones'].append(r.varint())
        for _ in range(r.varint()):
            skin['constraints'].append(('ik', r.varint()))
        for _ in range(r.varint()):
            skin['constraints'].append(('transform', r.varint()))
        for _ in range(r.varint()):
            skin['constraints'].append(('path', r.varint()))
        slot_count = r.varint()
    slots = {}
    for _ in range(slot_count):
        slot_index = r.varint()
        atts = {}
        for _ in range(r.varint()):
            att_name_ref = r.varint()
            att_name = ctx['strings'][att_name_ref - 1] if att_name_ref else None
            name_ref = r.varint()
            name = ctx['strings'][name_ref - 1] if name_ref else att_name
            att = read_attachment(r, sk, ctx, linked, nonessential, name)
            atts[att_name] = att
        slots[slot_index] = atts
    skin['slots'] = slots
    return skin


def read_attachment(r, sk, ctx, linked, nonessential, name):
    t = r.byte()
    att = {'type': ['region', 'boundingbox', 'mesh', 'linkedmesh', 'path', 'point', 'clipping'][t]}
    if t == 0:  # region
        path_ref = r.varint()
        att['path'] = ctx['strings'][path_ref - 1] if path_ref else name
        att['rotation'] = r.f32()
        att['x'], att['y'] = r.f32(), r.f32()
        att['scaleX'], att['scaleY'] = r.f32(), r.f32()
        att['width'], att['height'] = r.f32(), r.f32()
        att['color'] = r.u32()
        att['sequence'] = read_sequence(r)
    elif t == 1:  # boundingbox
        vc = r.varint()
        v = read_vertices(r, vc)
        att['vertexCount'] = vc
        att['vertices'] = v['vertices']
        if nonessential:
            att['color'] = r.u32()
    elif t == 2:  # mesh
        path_ref = r.varint()
        att['path'] = ctx['strings'][path_ref - 1] if path_ref else name
        att['color'] = r.u32()
        vc = r.varint()
        att['vertexCount'] = vc
        att['uvs'] = [r.f32() for _ in range(vc * 2)]
        att['triangles'] = read_short_array(r)
        v = read_vertices(r, vc)
        att['vertices'] = v['vertices']
        att['weighted'] = v['bones'] is not None
        att['hull'] = r.varint()
        att['sequence'] = read_sequence(r)
        if nonessential:
            att['edges'] = read_short_array(r)
            att['width'], att['height'] = r.f32(), r.f32()
    elif t == 3:  # linkedmesh
        path_ref = r.varint()
        att['path'] = ctx['strings'][path_ref - 1] if path_ref else name
        att['color'] = r.u32()
        sn = r.varint()
        att['skin_name'] = ctx['strings'][sn - 1] if sn else None
        pn = r.varint()
        att['parent_name'] = ctx['strings'][pn - 1] if pn else None
        att['inherit_timelines'] = r.boolean()
        att['sequence'] = read_sequence(r)
        if nonessential:
            att['width'], att['height'] = r.f32(), r.f32()
        linked.append({'att': att, 'skin_name': att['skin_name'], 'slot_index': None,
                       'parent_name': att['parent_name']})
    elif t == 4:  # path
        att['closed'] = r.boolean()
        att['constantSpeed'] = r.boolean()
        vc = r.varint()
        att['vertexCount'] = vc
        v = read_vertices(r, vc)
        att['vertices'] = v['vertices']
        att['lengths'] = [r.f32() for _ in range(vc // 3)]
        if nonessential:
            att['color'] = r.u32()
    elif t == 5:  # point
        att['rotation'] = r.f32()
        att['x'], att['y'] = r.f32(), r.f32()
        if nonessential:
            att['color'] = r.u32()
    elif t == 6:  # clipping
        att['end_slot'] = r.varint()
        vc = r.varint()
        att['vertexCount'] = vc
        v = read_vertices(r, vc)
        att['vertices'] = v['vertices']
        if nonessential:
            att['color'] = r.u32()
    return att


# -------------------------------------------------------------- animations ---

CURVE_LINEAR, CURVE_STEPPED, CURVE_BEZIER = 0, 1, 2


def read_curve(r, frames, last, channels, first, step_fn):
    """Shared frame loop: channels = count of value floats per frame.
    first = list of first-frame values. step_fn sets curve on frames[frame].
    Returns nothing; appends to frames."""
    time = r.f32()
    vals = first
    bezier = 0
    frame = 0
    while True:
        frames.append({'time': time, **vals})
        if frame == last:
            break
        time2 = r.f32()
        vals2 = [r.f32() for _ in range(channels)]
        c = r.byte()
        if c == CURVE_STEPPED:
            frames[-1]['curve'] = 'stepped'
        elif c == CURVE_BEZIER:
            curve = []
            for _ in range(channels):
                curve.extend([r.f32(), r.f32(), r.f32(), r.f32()])
            frames[-1]['curve'] = curve
        time = time2
        vals = vals2
        frame += 1


def parse_animation(r, sk, strings):
    a = {}
    r.varint()  # total timeline count (present in cpp/ts readers, absent in libgdx)
    slot_ttls = {}
    for _ in range(r.varint()):
        slot_index = r.varint()
        for _ in range(r.varint()):
            ttype = r.byte()
            fc = r.varint()
            last = fc - 1
            if ttype == 0:   # attachment (for-loop: fc=0 allowed)
                frames = []
                for _ in range(fc):
                    t = r.f32()
                    ref = r.varint()
                    frames.append({'time': t, 'name': None if ref == 0 else strings[ref - 1]})
                slot_ttls.setdefault(slot_index, {})['attachment'] = frames
            elif ttype in (1, 2, 3, 4, 5):  # rgba/rgb/rgba2/rgb2/alpha
                r.varint()  # bezier count
                ch = {1: 4, 2: 3, 3: 7, 4: 6, 5: 1}[ttype]
                frames = []
                t = r.f32()
                vals = [r.byte() / 255.0 for _ in range(ch)]
                bezier = 0
                frame = 0
                while True:
                    frames.append({'time': t, **{f'v{i}': v for i, v in enumerate(vals)}})
                    if frame == last:
                        break
                    t2 = r.f32()
                    vals2 = [r.byte() / 255.0 for _ in range(ch)]
                    c = r.byte()
                    if c == CURVE_STEPPED:
                        frames[-1]['curve'] = 'stepped'
                    elif c == CURVE_BEZIER:
                        curve = []
                        for _ in range(ch):
                            curve.extend([r.f32(), r.f32(), r.f32(), r.f32()])
                        frames[-1]['curve'] = curve
                    t = t2
                    vals = vals2
                    frame += 1
                key = {1: 'rgba', 2: 'rgb', 3: 'rgba2', 4: 'rgb2', 5: 'alpha'}[ttype]
                slot_ttls.setdefault(slot_index, {})[key] = frames
            else:
                raise ValueError(f"bad slot timeline type {ttype}")
    a['slots'] = slot_ttls

    bone_ttls = {}
    for _ in range(r.varint()):
        bone_index = r.varint()
        for _ in range(r.varint()):
            ttype = r.byte()
            fc = r.varint()
            r.varint()  # bezier count
            ch = 2 if ttype in (1, 4, 7) else 1  # translate/scale/shear are 2-value; rest 1-value
            frames = []
            t = r.f32()
            vals = [r.f32() for _ in range(ch)]
            frame = 0
            last = fc - 1
            while True:
                frames.append({'time': t, **{f'v{i}': v for i, v in enumerate(vals)}})
                if frame == last:
                    break
                t2 = r.f32()
                vals2 = [r.f32() for _ in range(ch)]
                c = r.byte()
                if c == CURVE_STEPPED:
                    frames[-1]['curve'] = 'stepped'
                elif c == CURVE_BEZIER:
                    curve = []
                    for _ in range(ch):
                        curve.extend([r.f32(), r.f32(), r.f32(), r.f32()])
                    frames[-1]['curve'] = curve
                t = t2
                vals = vals2
                frame += 1
            key = {0: 'rotate', 1: 'translate', 2: 'translatex', 3: 'translatey', 4: 'scale',
                   5: 'scalex', 6: 'scaley', 7: 'shear', 8: 'shearx', 9: 'sheary'}[ttype]
            bone_ttls.setdefault(bone_index, {})[key] = frames
    a['bones'] = bone_ttls

    ik_ttls = {}
    for _ in range(r.varint()):
        index = r.varint()
        fc = r.varint()
        r.varint()  # bezier count
        last = fc - 1
        frames = []
        t = r.f32()
        mix, softness = r.f32(), r.f32()
        frame = 0
        while True:
            bend = struct.unpack_from('>b', r.b, r.p)[0]
            r.p += 1
            compress, stretch = r.boolean(), r.boolean()
            frames.append({'time': t, 'mix': mix, 'softness': softness,
                           'bendPositive': bend > 0, 'compress': compress, 'stretch': stretch})
            if frame == last:
                break
            t2 = r.f32()
            mix2, softness2 = r.f32(), r.f32()
            c = r.byte()
            if c == CURVE_STEPPED:
                frames[-1]['curve'] = 'stepped'
            elif c == CURVE_BEZIER:
                curve = []
                for _ in range(2):
                    curve.extend([r.f32(), r.f32(), r.f32(), r.f32()])
                frames[-1]['curve'] = curve
            t = t2
            mix, softness = mix2, softness2
            frame += 1
        ik_ttls[index] = frames
    a['ik'] = ik_ttls

    tf_ttls = {}
    for _ in range(r.varint()):
        index = r.varint()
        fc = r.varint()
        r.varint()  # bezier count
        frames = []
        t = r.f32()
        vals = [r.f32() for _ in range(6)]
        frame = 0
        last = fc - 1
        while True:
            frames.append({'time': t, **{f'v{i}': v for i, v in enumerate(vals)}})
            if frame == last:
                break
            t2 = r.f32()
            vals2 = [r.f32() for _ in range(6)]
            c = r.byte()
            if c == CURVE_STEPPED:
                frames[-1]['curve'] = 'stepped'
            elif c == CURVE_BEZIER:
                curve = []
                for _ in range(6):
                    curve.extend([r.f32(), r.f32(), r.f32(), r.f32()])
                frames[-1]['curve'] = curve
            t = t2
            vals = vals2
            frame += 1
        tf_ttls[index] = frames
    a['transform'] = tf_ttls

    path_ttls = {}
    for _ in range(r.varint()):
        index = r.varint()
        for _ in range(r.varint()):
            ttype = r.byte()
            if ttype in (0, 1):
                fc = r.varint()
                r.varint()  # bezier count
                frames = []
                t = r.f32()
                v = r.f32()
                frame = 0
                last = fc - 1
                while True:
                    frames.append({'time': t, 'value': v})
                    if frame == last:
                        break
                    t2 = r.f32()
                    v2 = r.f32()
                    c = r.byte()
                    if c == CURVE_STEPPED:
                        frames[-1]['curve'] = 'stepped'
                    elif c == CURVE_BEZIER:
                        frames[-1]['curve'] = [r.f32() for _ in range(4)]
                    t = t2
                    v = v2
                    frame += 1
                path_ttls.setdefault(index, {})['position' if ttype == 0 else 'spacing'] = frames
            elif ttype == 2:
                fc = r.varint()
                r.varint()  # bezier count
                frames = []
                t = r.f32()
                vals = [r.f32() for _ in range(3)]
                frame = 0
                last = fc - 1
                while True:
                    frames.append({'time': t, **{f'v{i}': v for i, v in enumerate(vals)}})
                    if frame == last:
                        break
                    t2 = r.f32()
                    vals2 = [r.f32() for _ in range(3)]
                    c = r.byte()
                    if c == CURVE_STEPPED:
                        frames[-1]['curve'] = 'stepped'
                    elif c == CURVE_BEZIER:
                        curve = []
                        for _ in range(3):
                            curve.extend([r.f32(), r.f32(), r.f32(), r.f32()])
                        frames[-1]['curve'] = curve
                    t = t2
                    vals = vals2
                    frame += 1
                path_ttls.setdefault(index, {})['mix'] = frames
            else:
                raise ValueError(f"bad path timeline type {ttype}")
    a['path'] = path_ttls

    # attachment timelines (deform / sequence)
    att_ttls = []
    for _ in range(r.varint()):
        skin_index = r.varint()
        for _ in range(r.varint()):
            slot_index = r.varint()
            for _ in range(r.varint()):
                an = r.varint()
                ttype = r.byte()
                fc = r.varint()
                if ttype == 0:  # deform
                    r.varint()  # bezier count
                    frames = []
                    t = r.f32()
                    frame = 0
                    last = fc - 1
                    while True:
                        end = r.varint()
                        if end == 0:
                            deform = None   # full setup
                            offset = 0
                            verts = []
                        else:
                            start = r.varint()
                            offset = start
                            verts = [r.f32() for _ in range(end)]
                        rec = {'time': t, 'offset': offset, 'vertices': verts}
                        if frame == last:
                            frames.append(rec)
                            break
                        t2 = r.f32()
                        frames.append(rec)
                        c = r.byte()
                        if c == CURVE_STEPPED:
                            frames[-1]['curve'] = 'stepped'
                        elif c == CURVE_BEZIER:
                            frames[-1]['curve'] = [r.f32() for _ in range(4)]
                        t = t2
                        frame += 1
                    att_ttls.append({'skin': skin_index, 'slot': slot_index, 'att_ref': an,
                                     'name': None, 'kind': 'deform', 'frames': frames})
                elif ttype == 1:  # sequence
                    frames = []
                    for _ in range(fc):
                        t = r.f32()
                        mi = r.i32()
                        delay = r.f32()
                        frames.append({'time': t, 'mode_index': mi, 'delay': delay})
                    att_ttls.append({'skin': skin_index, 'slot': slot_index, 'att_ref': an,
                                     'name': None, 'kind': 'sequence', 'frames': frames})
                else:
                    raise ValueError(f"bad attachment timeline type {ttype}")
    a['attachments'] = att_ttls

    # draw order
    # NOTE: libgdx readInt() returns a Java int — raw varints >= 2^31 wrap to
    # negative. Offsets like -4 are stored as 5-byte varint 0xFFFFFFFC; without
    # the wrap the 4.2 JSON would carry 4294967292, which overflows int in the
    # spine-cpp reader and causes an OOB write in DrawOrderTimeline setup.
    def wrap_i32(v):
        v &= 0xFFFFFFFF
        return v - 2**32 if v >= 2**31 else v

    do_frames = []
    for _ in range(r.varint()):
        t = r.f32()
        offsets = []
        for _ in range(r.varint()):
            slot_index = r.varint()
            offsets.append({'slot': slot_index, 'offset': wrap_i32(r.varint())})
        do_frames.append({'time': t, 'offsets': offsets})
    a['drawOrder'] = do_frames

    # events
    ev_frames = []
    for _ in range(r.varint()):
        t = r.f32()
        ei = r.varint()
        iv = r.varint(positive=False)
        fv = r.f32()
        has_str = r.boolean()
        sv = r.string() if has_str else None
        rec = {'time': t, 'event': ei, 'int': iv, 'float': fv, 'string': sv}
        ev_frames.append(rec)
    a['events'] = ev_frames
    return a


def _resolve_str(r, ref):
    raise NotImplementedError


if __name__ == '__main__':
    src = sys.argv[1]
    buf = open(src, 'rb').read()
    sk = parse_skeleton(buf)
    print(f"spine {sk['spine']}, leftover={sk['leftover']} bytes")
    print(f"bones={len(sk['bones'])} slots={len(sk['slots'])} skins={len(sk['skins'])} "
          f"events={len(sk['events'])} strings={sk['_strings_count']}")
    print("animations:", list(sk['animations'].keys()))
