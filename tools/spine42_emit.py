"""Emit Spine 4.2 JSON from the spine41_parse model.

Targets spine-godot 4.2 (Slay the Spire 2): "spine" version string must
start with "4.2" or the runtime rejects the file. Supports animation
renaming (Ling -> STS2 names) and synthesizing missing animations.
"""
import json

TRANSFORM_MODES = ['normal', 'onlyTranslation', 'noRotationOrReflection', 'noScale', 'noScaleOrReflection']
POSITION_MODES = ['fixed', 'percent']
SPACING_MODES = ['length', 'fixed', 'percent']
ROTATE_MODES = ['tangent', 'chain', 'chainScale']
BLEND_MODES = ['normal', 'additive', 'multiply', 'screen']


def hexcolor(c, with_alpha=True):
    c &= 0xFFFFFFFF
    if with_alpha:
        return f'#{c:08x}'
    return f'#{(c >> 8):06x}'


def clean(v):
    r = round(v, 6)
    return int(r) if r == int(r) and abs(r) < 1e15 else r


def emit_bones(sk):
    bones = []
    for b in sk['bones']:
        d = {'name': b['name']}
        if b.get('parent', -1) >= 0:
            d['parent'] = sk['bones'][b['parent']]['name']
        if b['rotation']:
            d['rotation'] = clean(b['rotation'])
        if b['x']:
            d['x'] = clean(b['x'])
        if b['y']:
            d['y'] = clean(b['y'])
        if b['scaleX'] != 1:
            d['scaleX'] = clean(b['scaleX'])
        if b['scaleY'] != 1:
            d['scaleY'] = clean(b['scaleY'])
        if b['shearX']:
            d['shearX'] = clean(b['shearX'])
        if b['shearY']:
            d['shearY'] = clean(b['shearY'])
        if b['length']:
            d['length'] = clean(b['length'])
        tm = TRANSFORM_MODES[b['transform_mode']]
        if tm != 'normal':
            d['inherit'] = tm
        if b['skin_required']:
            d['skin'] = True
        if sk.get('nonessential') and 'color' in b:
            d['color'] = hexcolor(b['color'])
        bones.append(d)
    return bones


def emit_slots(sk):
    slots = []
    for s in sk['slots']:
        d = {'name': s['name'], 'bone': sk['bones'][s['bone']]['name']}
        if s['color'] != 0xFFFFFFFF:
            d['color'] = hexcolor(s['color'])
        if s['dark'] != -1:
            d['dark'] = hexcolor(s['dark'], with_alpha=False)
        if s['attachment']:
            d['attachment'] = s['attachment']
        blend = BLEND_MODES[s['blend']]
        if blend != 'normal':
            d['blend'] = blend
        slots.append(d)
    return slots


def emit_ik(sk):
    out = []
    for i, c in enumerate(sk['ik']):
        d = {'name': c['name']}
        if c['order'] != i:
            d['order'] = c['order']
        if c['skin_required']:
            d['skin'] = True
        d['bones'] = [sk['bones'][b]['name'] for b in c['bones']]
        d['target'] = sk['bones'][c['target']]['name']
        d['mix'] = clean(c['mix'])
        if c['softness']:
            d['softness'] = clean(c['softness'])
        d['bendPositive'] = c['bend_direction'] > 0
        if c['compress']:
            d['compress'] = True
        if c['stretch']:
            d['stretch'] = True
        if c['uniform']:
            d['uniform'] = True
        out.append(d)
    return out


def emit_transform(sk):
    out = []
    for i, c in enumerate(sk['transform']):
        d = {'name': c['name']}
        if c['order'] != i:
            d['order'] = c['order']
        if c['skin_required']:
            d['skin'] = True
        d['bones'] = [sk['bones'][b]['name'] for b in c['bones']]
        d['target'] = sk['bones'][c['target']]['name']
        if c['local']:
            d['local'] = True
        if c['relative']:
            d['relative'] = True
        if c['offsetRotation']:
            d['rotation'] = clean(c['offsetRotation'])
        if c['offsetX']:
            d['x'] = clean(c['offsetX'])
        if c['offsetY']:
            d['y'] = clean(c['offsetY'])
        if c['offsetScaleX'] != 1:
            d['scaleX'] = clean(c['offsetScaleX'])
        if c['offsetScaleY'] != 1:
            d['scaleY'] = clean(c['offsetScaleY'])
        if c['offsetShearY']:
            d['shearY'] = clean(c['offsetShearY'])
        for k in ('mixRotate', 'mixX', 'mixY', 'mixScaleX', 'mixScaleY', 'mixShearY'):
            d[k] = clean(c[k])
        out.append(d)
    return out


def emit_path(sk):
    out = []
    for i, c in enumerate(sk['path']):
        d = {'name': c['name']}
        if c['order'] != i:
            d['order'] = c['order']
        if c['skin_required']:
            d['skin'] = True
        d['bones'] = [sk['bones'][b]['name'] for b in c['bones']]
        d['target'] = sk['slots'][c['target']]['name']
        d['positionMode'] = POSITION_MODES[c['positionMode']]
        d['spacingMode'] = SPACING_MODES[c['spacingMode']]
        d['rotateMode'] = ROTATE_MODES[c['rotateMode']]
        if c['offsetRotation']:
            d['rotation'] = clean(c['offsetRotation'])
        d['position'] = clean(c['position'])
        d['spacing'] = clean(c['spacing'])
        d['mixRotate'] = clean(c['mixRotate'])
        d['mixX'] = clean(c['mixX'])
        d['mixY'] = clean(c['mixY'])
        out.append(d)
    return out


def emit_attachment(att, att_name, nonessential, slot_names):
    t = att['type']
    d = {}
    if t != 'region':
        d['type'] = t
    if att.get('path') and att['path'] != att_name:
        d['path'] = att['path']
    if 'color' in att and att['color'] != 0xFFFFFFFF:
        d['color'] = hexcolor(att['color'])
    if t == 'region':
        if att['rotation']:
            d['rotation'] = clean(att['rotation'])
        if att['x']:
            d['x'] = clean(att['x'])
        if att['y']:
            d['y'] = clean(att['y'])
        if att['scaleX'] != 1:
            d['scaleX'] = clean(att['scaleX'])
        if att['scaleY'] != 1:
            d['scaleY'] = clean(att['scaleY'])
        d['width'] = clean(att['width'])
        d['height'] = clean(att['height'])
    elif t == 'mesh':
        d['uvs'] = [clean(v) for v in att['uvs']]
        d['triangles'] = att['triangles']
        d['vertices'] = [clean(v) for v in att['vertices']]
        d['hull'] = att['hull']
        if nonessential and 'edges' in att:
            d['edges'] = att['edges']
            d['width'] = clean(att['width'])
            d['height'] = clean(att['height'])
    elif t == 'linkedmesh':
        if att.get('skin_name'):
            d['skin'] = att['skin_name']
        d['parent'] = att['parent_name']
        if not att['inherit_timelines']:
            d['deform'] = False
        if nonessential and 'width' in att:
            d['width'] = clean(att['width'])
            d['height'] = clean(att['height'])
    elif t == 'boundingbox':
        d['vertexCount'] = att['vertexCount']
        d['vertices'] = [clean(v) for v in att['vertices']]
    elif t == 'path':
        if att['closed']:
            d['closed'] = True
        if not att['constantSpeed']:
            d['constantSpeed'] = False
        d['vertexCount'] = att['vertexCount']
        d['vertices'] = [clean(v) for v in att['vertices']]
        d['lengths'] = [clean(v) for v in att['lengths']]
    elif t == 'point':
        if att['rotation']:
            d['rotation'] = clean(att['rotation'])
        d['x'] = clean(att['x'])
        d['y'] = clean(att['y'])
    elif t == 'clipping':
        end_slot = att['end_slot']
        d['end'] = slot_names[end_slot] if 0 <= end_slot < len(slot_names) else ''
        d['vertexCount'] = att['vertexCount']
        d['vertices'] = [clean(v) for v in att['vertices']]
    if att.get('sequence'):
        sq = att['sequence']
        d['sequence'] = {'count': sq['count'], 'start': sq['start'],
                         'digits': sq['digits'], 'setupIndex': sq['setupIndex']}
    return d


def emit_skins(sk):
    nonessential = sk.get('nonessential', False)
    slot_names = [s['name'] for s in sk['slots']]
    constraint_lists = {'ik': sk['ik'], 'transform': sk['transform'], 'path': sk['path']}
    skins = []
    for skin in sk['skins']:
        entry = {'name': skin['name'] or 'default'}
        if skin['bones']:
            entry['bones'] = [sk['bones'][b]['name'] for b in skin['bones']]
        for kind, idx in skin['constraints']:
            entry.setdefault(kind, []).append(constraint_lists[kind][idx]['name'])
        atts_out = {}
        for slot_index, atts in skin['slots'].items():
            slot_name = slot_names[slot_index]
            att_map = {}
            for att_name, att in atts.items():
                att_map[att_name] = emit_attachment(att, att_name, nonessential, slot_names)
            if att_map:
                atts_out[slot_name] = att_map
        if atts_out:
            entry['attachments'] = atts_out
        skins.append(entry)
    return skins


def emit_events(sk):
    out = []
    for e in sk['events']:
        d = {'name': sk['_strings'][e['name'] - 1] if e['name'] else None}
        if e['int']:
            d['int'] = e['int']
        if e['float']:
            d['float'] = clean(e['float'])
        if e['string']:
            d['string'] = e['string']
        if e['audio'] is not None:
            d['audio'] = e['audio']
            d['volume'] = clean(e.get('volume', 0))
            d['balance'] = clean(e.get('balance', 0))
        out.append(d)
    return out


def emit_animation(a, sk, skin_names):
    strings = sk['_strings']
    slot_names = [s['name'] for s in sk['slots']]
    bone_names = [b['name'] for b in sk['bones']]
    out = {}
    # slots
    if a['slots']:
        slots_out = {}
        for si, tls in a['slots'].items():
            slot_out = {}
            for kind, frames in tls.items():
                fl = []
                for fr in frames:
                    d = {'time': clean(fr['time'])}
                    if kind == 'attachment':
                        d['name'] = fr['name']
                    else:
                        # spine41_parse keys slot color timelines by NAME
                        # ({1:'rgba',2:'rgb',3:'rgba2',4:'rgb2',5:'alpha'}).
                        # 4.2 slot color frames are HEX STRINGS: "color":
                        # "#rrggbbaa" (two-color adds "color2": "#rrggbb") —
                        # numeric r/g/b/a keys crash the parsers.
                        def _b(v):
                            return max(0, min(255, int(round(v * 255))))
                        if kind == 'rgba':
                            d['color'] = '#%02x%02x%02x%02x' % (_b(fr['v0']), _b(fr['v1']), _b(fr['v2']), _b(fr['v3']))
                        elif kind == 'rgb':
                            d['color'] = '#%02x%02x%02x' % (_b(fr['v0']), _b(fr['v1']), _b(fr['v2']))
                        elif kind == 'alpha':
                            d['color'] = '#000000%02x' % _b(fr['v0'])
                        elif kind in ('rgba2', 'rgb2'):
                            # two-color timelines read "light"/"dark" in
                            # spine-cpp (SkeletonJson.cpp toColor(getString
                            # "light"/"dark")) — "color"/"color2" crash it
                            if kind == 'rgba2':
                                d['light'] = '#%02x%02x%02x%02x' % (_b(fr['v0']), _b(fr['v1']), _b(fr['v2']), _b(fr['v3']))
                            else:
                                d['light'] = '#%02x%02x%02x' % (_b(fr['v0']), _b(fr['v1']), _b(fr['v2']))
                            d['dark'] = '#%02x%02x%02x' % (_b(fr['v4']), _b(fr['v5']), _b(fr['v6']))
                        else:
                            raise ValueError(f'bad slot color kind {kind}')
                    if 'curve' in fr:
                        d['curve'] = fr['curve'] if fr['curve'] == 'stepped' else [clean(x) for x in fr['curve']]
                    fl.append(d)
            slot_out[kind] = fl
            slots_out[slot_names[si]] = slot_out
        out['slots'] = slots_out
    # bones
    if a['bones']:
        bones_out = {}
        for bi, tls in a['bones'].items():
            bone_out = {}
            # 4.2 JSON key names (spine-cpp SkeletonJson::readTimeline):
            # two-value timelines read "x"/"y"; ALL single-value timelines
            # (rotate/translatex/translatey/scalex/scaley/shearx/sheary) read
            # "value" — 4.0-style "angle" makes every rotation default to 0.
            vkey = {'rotate': ('value',), 'translate': ('x', 'y'), 'translatex': ('value',), 'translatey': ('value',),
                    'scale': ('x', 'y'), 'scalex': ('value',), 'scaley': ('value',), 'shear': ('x', 'y'),
                    'shearx': ('value',), 'sheary': ('value',)}
            for kind, frames in tls.items():
                fl = []
                for fr in frames:
                    d = {'time': clean(fr['time'])}
                    keys = vkey[kind]
                    for k, v in zip(keys, [fr[f'v{i}'] for i in range(len(keys))]):
                        d[k] = clean(v)
                    if 'curve' in fr:
                        d['curve'] = fr['curve'] if fr['curve'] == 'stepped' else [clean(x) for x in fr['curve']]
                    fl.append(d)
                bone_out[kind] = fl
            bones_out[bone_names[bi]] = bone_out
        out['bones'] = bones_out
    # ik
    if a['ik']:
        out['ik'] = {sk['ik'][i]['name']: [
            {**{'time': clean(fr['time']), 'mix': clean(fr['mix']), 'softness': clean(fr['softness']),
                'bendPositive': fr['bendPositive'], 'compress': fr['compress'], 'stretch': fr['stretch']},
             **({'curve': fr['curve']} if 'curve' in fr else {})}
            for fr in frames] for i, frames in a['ik'].items()}
    # transform
    if a['transform']:
        tkeys = ['mixRotate', 'mixX', 'mixY', 'mixScaleX', 'mixScaleY', 'mixShearY']
        out['transform'] = {sk['transform'][i]['name']: [
            {**{'time': clean(fr['time'])},
             **{k: clean(fr[f'v{j}']) for j, k in enumerate(tkeys)},
             **({'curve': fr['curve']} if 'curve' in fr else {})}
            for fr in frames] for i, frames in a['transform'].items()}
    # path
    if a['path']:
        path_out = {}
        for i, kinds in a['path'].items():
            pname = sk['path'][i]['name']
            po = {}
            for kind, frames in kinds.items():
                if kind == 'mix':
                    po['mix'] = [{**{'time': clean(fr['time']), 'mixRotate': clean(fr['v0']),
                                     'mixX': clean(fr['v1']), 'mixY': clean(fr['v2'])},
                                  **({'curve': fr['curve']} if 'curve' in fr else {})} for fr in frames]
                else:
                    po[kind] = [{**{'time': clean(fr['time']), 'value': clean(fr['value'])},
                                 **({'curve': fr['curve']} if 'curve' in fr else {})} for fr in frames]
            path_out[pname] = po
        out['path'] = path_out
    # attachments (deform / sequence)
    if a['attachments']:
        att_out = {}
        for rec in a['attachments']:
            skin = sk['skins'][rec['skin']] if rec['skin'] < len(sk['skins']) else None
            if skin is None or rec['slot'] not in skin['slots']:
                continue
            slot_name = slot_names[rec['slot']]
            atts = skin['slots'][rec['slot']]
            # att_ref is a strings-table reference (binary readStringRef), not an index
            strings = sk.get('_strings') or []
            att_name = strings[rec['att_ref'] - 1] if 0 < rec['att_ref'] <= len(strings) else None
            if not att_name or att_name not in atts:
                continue
            # 4.2 nests attachment timelines three levels deep:
            # attachments.<skinName>.<slotName>.<attachmentName>
            skin_map = att_out.setdefault(skin['name'], {})
            slot_map = skin_map.setdefault(slot_name, {})
            att_map = slot_map.setdefault(att_name, {})
            if rec['kind'] == 'deform':
                fl = []
                for fr in rec['frames']:
                    d = {'time': clean(fr['time'])}
                    if fr['vertices']:
                        d['offset'] = fr['offset']
                        d['vertices'] = [clean(v) for v in fr['vertices']]
                    if 'curve' in fr:
                        d['curve'] = fr['curve'] if fr['curve'] == 'stepped' else [clean(x) for x in fr['curve']]
                    fl.append(d)
                att_map['deform'] = fl
            else:
                att_map['sequence'] = [{'time': clean(fr['time']), 'mode': fr['mode_index'] & 0xF,
                                        'index': fr['mode_index'] >> 4, 'delay': clean(fr['delay'])}
                                       for fr in rec['frames']]
        if att_out:
            out['attachments'] = att_out
    # draw order
    if a['drawOrder']:
        out['drawOrder'] = [{'time': clean(fr['time']),
                             'offsets': [{'slot': slot_names[o['slot']], 'offset': o['offset']}
                                         for o in fr['offsets']]} for fr in a['drawOrder']]
    # events
    if a['events']:
        ev_out = []
        for fr in a['events']:
            data = sk['events'][fr['event']] if fr['event'] < len(sk['events']) else None
            name = strings[data['name'] - 1] if data and data['name'] else None
            d = {'time': clean(fr['time']), 'name': name}
            if fr['int']:
                d['int'] = fr['int']
            if fr['float']:
                d['float'] = clean(fr['float'])
            if fr['string'] is not None:
                d['string'] = fr['string']
            elif data and data['string']:
                d['string'] = data['string']
            audio = data['audio'] if data else None
            if audio is not None:
                d['volume'] = clean(fr.get('volume', data.get('volume', 0)))
                d['balance'] = clean(fr.get('balance', data.get('balance', 0)))
            ev_out.append(d)
        out['events'] = ev_out
    return out


def emit_json(sk, anim_rename=None, extra_animations=None, spine_version='4.2.43'):
    root = {}
    skel = {'hash': sk.get('hash'), 'spine': spine_version}
    for k in ('x', 'y', 'width', 'height'):
        skel[k] = clean(sk[k])
    if sk.get('nonessential'):
        if 'fps' in sk:
            skel['fps'] = clean(sk['fps'])
        if sk.get('images'):
            skel['images'] = sk['images']
        if sk.get('audio'):
            skel['audio'] = sk['audio']
    root['skeleton'] = skel
    root['bones'] = emit_bones(sk)
    root['slots'] = emit_slots(sk)
    if sk['ik']:
        root['ik'] = emit_ik(sk)
    if sk['transform']:
        root['transform'] = emit_transform(sk)
    if sk['path']:
        root['path'] = emit_path(sk)
    root['skins'] = emit_skins(sk)
    if sk['events']:
        root['events'] = emit_events(sk)
    anims = {}
    for name, a in sk['animations'].items():
        out_name = (anim_rename or {}).get(name, name)
        anims[out_name] = emit_animation(a, sk, [s['name'] or 'default' for s in sk['skins']])
    for name, a in (extra_animations or {}).items():
        anims[name] = a
    root['animations'] = anims
    return root
