#!/usr/bin/env python3
"""Rebuild the die animation with CORRECT endpoint poses.

Bug being fixed (found via the offline pose strip): the previous die build
iterated the UNION of idle_loop/stand timelines and sampled each at t=0 and
t=0.8 - but for timelines that exist ONLY in stand (legs/hips/body), the t=0
sample returned stand@0, so die STARTED with stand legs. In game the death
cut snaps those bones from idle stance to stand stance in ONE frame (only the
arm chain glides) => the user sees an "instant stand".

Correct rule: for every (bone, channel) in the union,
  t=0   value = idle_loop's value at t=0 if animated there, else SETUP value
  t=0.8 value = stand's value at t=0 if animated there, else SETUP value
  t=2.0 value = same as t=0.8 (hold)
Slot rgba fade keys are preserved untouched.
"""
import json
import sys
from pathlib import Path

SRC = Path(r'D:/项目/dragonraja/sts2_work/LingSilentSkin_mod/_pcksrc/ling/animations/characters/silent/ling.json')

# Spine timeline keys are ADDITIVE offsets (rotate/translate/shear) or
# MULTIPLIERS (scale) relative to the bone's SETUP values - proven by the
# runtime: idle bone10 read 218.8 = setup 170.57 + idle key 47.42. So the
# neutral element for "this animation doesn't animate this channel" is:
NEUTRAL = {
    'rotate': 0.0,
    'translate': (0.0, 0.0),
    'scale': (1.0, 1.0),
    'shear': (0.0, 0.0),
}


def value_at_time0(timeline, channel):
    """Channel value at t=0; neutral element if not animated / first key > 0."""
    frames = (timeline or {}).get(channel)
    neutral = NEUTRAL[channel]
    if not frames:
        return neutral
    first = frames[0]
    if first.get('time', 0) > 0:
        return neutral
    if channel == 'rotate':
        return first.get('value', neutral)
    return (first.get('x', neutral[0]), first.get('y', neutral[1]))


def main():
    j = json.loads(SRC.read_text(encoding='utf-8'))
    bones = {b['name']: b for b in j['bones']}
    idle_bones = j['animations']['idle_loop'].get('bones', {})
    stand_bones = j['animations']['stand'].get('bones', {})
    old_die = j['animations']['die']
    rgba_slots = old_die.get('slots', {})  # keep the 2.0->2.1 fade

    new_bone_tls = {}
    union = set(idle_bones) | set(stand_bones)
    stats = {'bones': 0, 'channels': 0, 'static': 0}
    for name in sorted(union):
        bone_tls = {}
        for channel in ('rotate', 'translate', 'scale', 'shear'):
            iv = value_at_time0(idle_bones.get(name, {}), channel)
            sv = value_at_time0(stand_bones.get(name, {}), channel)
            if channel not in idle_bones.get(name, {}) and channel not in stand_bones.get(name, {}):
                continue  # bone/channel not animated by either pose source
            same = abs(iv[0] - sv[0]) < 1e-6 if isinstance(iv, tuple) else abs(iv - sv) < 1e-6
            if same:
                stats['static'] += 1
                # identical in both poses: write a static key so the bone is
                # pinned to that value regardless of the interrupted animation
                key = {'time': 0.0, 'value': iv} if channel == 'rotate' else {'time': 0.0, 'x': iv[0], 'y': iv[1]}
                bone_tls[channel] = [key, dict(key, time=0.8), dict(key, time=2.0)]
                stats['channels'] += 1
                continue
            if channel == 'rotate':
                bone_tls[channel] = [
                    {'time': 0.0, 'value': iv},
                    {'time': 0.8, 'value': sv},
                    {'time': 2.0, 'value': sv},
                ]
            else:
                bone_tls[channel] = [
                    {'time': 0.0, 'x': iv[0], 'y': iv[1]},
                    {'time': 0.8, 'x': sv[0], 'y': sv[1]},
                    {'time': 2.0, 'x': sv[0], 'y': sv[1]},
                ]
            stats['channels'] += 1
        if bone_tls:
            new_bone_tls[name] = bone_tls
            stats['bones'] += 1

    j['animations']['die'] = {
        'bones': new_bone_tls,
        'slots': rgba_slots,
    }
    SRC.write_text(json.dumps(j, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print('rebuilt die:', stats)
    # sanity: sample a few leg bones to prove t=0 now equals idle pose
    for bn in ['bone24', 'bone44', 'bone43', 'bone10', 'bone11']:
        tl = new_bone_tls.get(bn, {}).get('rotate')
        if tl:
            print(f'  {bn}: t0={tl[0]["value"]:.1f} t0.8={tl[1]["value"]:.1f}')
        else:
            print(f'  {bn}: (no rotate timeline)')


if __name__ == '__main__':
    sys.exit(main())
