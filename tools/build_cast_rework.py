#!/usr/bin/env python3
"""Rework the battle 'cast' animation from SOURCE spine data (user-approved plan).

源速=游戏速,总长 0.9225s,不经过 build_ling_assets 的 speed=2.0 调速:
  S1 skill01_1 0.0000-0.3000 @1.5x -> 0.0000-0.2000
  S2 skill01_1 0.3000-0.5333 @1.5x -> 0.2000-0.3556
  S3 skill01_1@0.5333 -> skill01_3@0.4000 自然补帧 0.067s -> 0.3556-0.4226
  S4 skill01_3 0.4000-0.4333 @1x   -> 0.4226-0.4559
  S5 skill01_3 0.4333-0.6667 @1.5x -> 0.4559-0.6114
  S6 skill01_3 0.6667-0.8333 @1.5x -> 0.6114-0.7225
  S7 skill01_3 0.8333-1.1000 @2x   -> 0.7225-0.8559
  S8 skill01_3 1.1000-1.2333 @2x   -> 0.8559-0.9225
段内全部为原生关键帧(时间重映射,bezier 控制点时间同步变换);
仅 S3 补帧段两端点为合成键——端点时刻均为原生关键帧时刻,对端点处
无原生键的时间轴由相邻原生键线性求值。

用法: python tools/build_cast_rework.py  (写回 _pcksrc 的 ling.json)
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))

import az_spine_extract as ase  # noqa: E402
import spine41_parse as sp  # noqa: E402
import spine42_emit as em  # noqa: E402

SRC_CHAR = ROOT / 'unpacked/res_models/characters/ling001'
SRC_STEM = 'chr_ling001'
PRODUCT = ROOT / 'sts2_work/LingSilentSkin_mod/_pcksrc/ling/animations/characters/silent/ling.json'

# (anim, in0, in1, out0, speed) —— 半开区间 [in0, in1),末段含 in1
T = lambda n: n / 30.0  # 源动画 fps=30,所有原生关键帧时刻 = n/30
SEGS = [
    ('skill01_1', 0.0,    T(9),  0.0,      1.5),
    ('skill01_1', T(9),  T(16),  0.2,      1.5),
    ('skill01_3', T(12), T(13),  0.422556, 1.0),
    ('skill01_3', T(13), T(20),  0.455889, 1.5),
    ('skill01_3', T(20), T(25),  0.611444, 1.5),
    ('skill01_3', T(25), T(33),  0.722511, 2.0),
    ('skill01_3', T(33), T(37),  0.855856, 2.0),
]
LAST_IN = T(37)
B0, B1 = 0.355556, 0.422556          # S3 补帧输出区间
BLEND_AT = {'skill01_1': T(16), 'skill01_3': T(12)}
VAL_KEYS = {'rotate': ['angle'], 'translate': ['x', 'y'], 'scale': ['x', 'y'], 'shear': ['x', 'y']}


def load_source_anims():
    uexp = (SRC_CHAR / f'{SRC_STEM}-data.uexp').read_bytes()
    skel_bytes, _ = ase.locate_spine(uexp)
    sk = sp.parse_skeleton(skel_bytes)
    assert sk['leftover'] == 0, sk['leftover']
    root = em.emit_json(sk, anim_rename={}, extra_animations={})
    return root


def map_time(anim, t):
    """源时刻 -> 新 cast 输出时刻;不在保留区间返回 None。"""
    if anim == 'skill01_1':
        if 0.0 <= t <= T(9):
            return t / 1.5
        if T(9) < t <= T(16):
            return 0.2 + (t - T(9)) / 1.5
        return None
    if T(12) < t <= T(13):
        return 0.422556 + (t - T(12))
    if T(13) < t <= T(20):
        return 0.455889 + (t - T(13)) / 1.5
    if T(20) < t <= T(25):
        return 0.611444 + (t - T(20)) / 1.5
    if T(25) < t <= T(33):
        return 0.722511 + (t - T(25)) / 2
    if T(33) < t <= T(37):
        return 0.855856 + (t - T(33)) / 2
    return None


def remap_frame(f, anim):
    out = {'time': round(map_time(anim, f['time']), 6)}
    for k, v in f.items():
        if k in ('time', 'curve'):
            continue
        out[k] = v
    c = f.get('curve')
    if c == 'stepped':
        out['curve'] = 'stepped'
    elif isinstance(c, list) and len(c) == 4:
        out0 = out['time'] - (f['time'] - map_seg_in0(anim, f['time'])) / map_seg_speed(anim, f['time'])
        c1 = out0 + (c[0] - map_seg_in0(anim, f['time'])) / map_seg_speed(anim, f['time'])
        c2 = out0 + (c[2] - map_seg_in0(anim, f['time'])) / map_seg_speed(anim, f['time'])
        out['curve'] = [round(c1, 6), c[1], round(c2, 6), c[3]]
    return out


_SEG_CACHE = None


def map_seg_in0(anim, t):
    for a, in0, in1, out0, speed in _seg_iter():
        if a == anim and in0 <= t <= in1:
            return in0
    return 0.0


def map_seg_speed(anim, t):
    for a, in0, in1, out0, speed in _seg_iter():
        if a == anim and in0 <= t <= in1:
            return speed
    return 1.0


def _seg_iter():
    global _SEG_CACHE
    if _SEG_CACHE is None:
        _SEG_CACHE = SEGS + [('skill01_3', LAST_IN, LAST_IN, 0.922511, 2.0)]
    return _SEG_CACHE


def copy_timeline(frames, anim):
    out = []
    for f in frames:
        t = f['time']
        mt = map_time(anim, t)
        if mt is None:
            continue
        nf = {'time': round(mt, 6)}
        for k, v in f.items():
            if k in ('time', 'curve'):
                continue
            nf[k] = v
        c = f.get('curve')
        if c == 'stepped':
            nf['curve'] = 'stepped'
        elif isinstance(c, list) and len(c) == 4:
            in0 = map_seg_in0(anim, t)
            speed = map_seg_speed(anim, t)
            base = mt - (t - in0) / speed
            c1 = base + (c[0] - in0) / speed
            c2 = base + (c[2] - in0) / speed
            nf['curve'] = [round(c1, 6), c[1], round(c2, 6), c[3]]
        out.append(nf)
    return out


def frame_vals(f, kind):
    if kind == 'attachment':
        return {'name': f.get('name')}
    return {k: f[k] for k in VAL_KEYS.get(kind, []) if k in f}


def lerp_frame_vals(v0, v1, w):
    out = {}
    for k in v0:
        a, b = v0[k], v1.get(k, v0[k])
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            out[k] = round(a + (b - a) * w, 6)
        else:
            out[k] = a if w < 0.5 else b
    return out


def eval_track(frames, t, kind):
    if t <= frames[0]['time']:
        return frame_vals(frames[0], kind)
    if t >= frames[-1]['time']:
        return frame_vals(frames[-1], kind)
    for i in range(len(frames) - 1):
        t0, t1 = frames[i]['time'], frames[i + 1]['time']
        if t0 <= t <= t1:
            w = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            return lerp_frame_vals(frame_vals(frames[i], kind), frame_vals(frames[i + 1], kind), w)
    return frame_vals(frames[-1], kind)


def active_attachment(frames, t, setup):
    name = setup
    for f in frames:
        if f['time'] <= t and f.get('name'):
            name = f['name']
    return name


def dedupe(frames):
    frames = sorted(frames, key=lambda f: f['time'])
    out = []
    for f in frames:
        if out and abs(out[-1]['time'] - f['time']) < 1e-6:
            out[-1] = f
        else:
            out.append(f)
    return out


def setup_val(bones_setup, kind):
    return {'rotate': {'angle': 0.0}, 'translate': {'x': 0.0, 'y': 0.0},
            'scale': {'x': 1.0, 'y': 1.0}, 'shear': {'x': 0.0, 'y': 0.0}}[kind]


def main():
    src = load_source_anims()
    a1 = src['animations']['skill01_1']
    a3 = src['animations']['skill01_3']
    bones_setup = {b['name']: b for b in src['bones']}

    new_cast = {'bones': {}, 'slots': {}}
    stat = {'copied': 0, 'dropped': 0, 'blend_tracks': 0, 'blend_synth': 0}

    # --- bones ---
    bone_union = {}
    for anim, anim_data in (('skill01_1', a1), ('skill01_3', a3)):
        for bname, tls in anim_data.get('bones', {}).items():
            bone_union.setdefault(bname, {}).setdefault('kinds', set()).update(tls.keys())
            bone_union[bname].setdefault('srcs', set()).add(anim)
    for bname, info in bone_union.items():
        for kind in sorted(info['kinds']):
            frames = []
            for anim, anim_data in (('skill01_1', a1), ('skill01_3', a3)):
                tl = anim_data.get('bones', {}).get(bname, {}).get(kind)
                if tl:
                    frames += copy_timeline(tl, anim)
                    stat['copied'] += len(tl)
            # blend 段合成键(该骨骼时间轴在任一源动画中存在即参与)
            tlA = a1.get('bones', {}).get(bname, {}).get(kind)
            tlB = a3.get('bones', {}).get(bname, {}).get(kind)
            setup = setup_val(bones_setup.get(bname, {}), kind)
            vA = eval_track(tlA, BLEND_AT['skill01_1'], kind) if tlA else setup
            vB = eval_track(tlB, BLEND_AT['skill01_3'], kind) if tlB else setup
            fa = {'time': round(B0, 6), **vA}
            fb = {'time': round(B1, 6), **vB}
            if json.dumps(vA, sort_keys=True) != json.dumps(vB, sort_keys=True):
                frames += [fa, fb]
                stat['blend_synth'] += 2
            else:
                frames += [fa]
                stat['blend_synth'] += 1
            stat['blend_tracks'] += 1
            frames = dedupe(frames)
            if frames:
                new_cast['bones'].setdefault(bname, {})[kind] = frames

    # --- slots (attachment 时间轴,stepped) ---
    slot_union = {}
    for anim, anim_data in (('skill01_1', a1), ('skill01_3', a3)):
        for sname, tls in anim_data.get('slots', {}).items():
            slot_union.setdefault(sname, set()).update(tls.keys())
    slots_setup = {s['name']: s.get('attachment', '') for s in src['slots']}
    for sname in sorted(slot_union):
        for kind in sorted(slot_union[sname]):
            frames = []
            for anim, anim_data in (('skill01_1', a1), ('skill01_3', a3)):
                tl = anim_data.get('slots', {}).get(sname, {}).get(kind)
                if tl:
                    frames += copy_timeline(tl, anim)
            if kind == 'attachment':
                tlA = a1.get('slots', {}).get(sname, {}).get('attachment')
                tlB = a3.get('slots', {}).get(sname, {}).get('attachment')
                setup = slots_setup.get(sname, '')
                nA = active_attachment(tlA, BLEND_AT['skill01_1'], setup) if tlA else setup
                nB = active_attachment(tlB, BLEND_AT['skill01_3'], setup) if tlB else setup
                if nA != nB:
                    frames += [{'time': round(B0, 6), 'name': nA},
                               {'time': round(B1, 6), 'name': nB}]
                    stat['blend_synth'] += 2
                else:
                    frames += [{'time': round(B0, 6), 'name': nA}]
                    stat['blend_synth'] += 1
            frames = dedupe(frames)
            if frames:
                new_cast['slots'].setdefault(sname, {})[kind] = frames

    # --- drawOrder ---
    do_frames = []
    for anim, anim_data in (('skill01_1', a1), ('skill01_3', a3)):
        for f in anim_data.get('drawOrder', []):
            mt = map_time(anim, f['time'])
            if mt is None:
                stat['dropped'] += 1
                continue
            nf = {'time': round(mt, 6)}
            nf.update({k: v for k, v in f.items() if k != 'time'})
            do_frames.append(nf)
    if do_frames:
        new_cast['drawOrder'] = dedupe(do_frames)

    dur = 0.0

    def mt(o):
        nonlocal dur
        if isinstance(o, dict):
            for k, v in o.items():
                if k == 'time' and isinstance(v, (int, float)):
                    dur = max(dur, v)
                else:
                    mt(v)
        elif isinstance(o, list):
            for v in o:
                mt(v)
    mt(new_cast)

    product = json.loads(PRODUCT.read_bytes())
    product['animations']['cast'] = new_cast
    PRODUCT.write_text(json.dumps(product, ensure_ascii=False, separators=(',', ':')),
                       encoding='utf-8')
    print(f"new cast written: dur={dur:.6f}s copied={stat['copied']} "
          f"blend_tracks={stat['blend_tracks']} blend_synth={stat['blend_synth']} "
          f"drawOrder_dropped={stat['dropped']}")


if __name__ == '__main__':
    main()
