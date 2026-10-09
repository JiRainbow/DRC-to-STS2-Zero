import sys, json
sys.path.insert(0, 'tools')
from pathlib import Path
import az_spine_extract as ase
import spine41_parse as sp
import spine42_emit as em

SRC = Path('render_work/pd_ling2/s_plotdrawing/spd_ling')
uexp = (SRC / 's_plotdrawing_ling-data.uexp').read_bytes()
skel_bytes, _ = ase.locate_spine(uexp)
sk = sp.parse_skeleton(skel_bytes)
anims = sk['animations']
print('parse-level animations:', list(anims.keys()))
for nm, a in anims.items():
    slots = a.get('slots')
    print(f'[{nm}] slots container type:', type(slots).__name__)
    entries = slots.items() if isinstance(slots, dict) else enumerate(slots or [])
    for key, tls in entries:
        s = json.dumps(tls, default=str)
        if 'windows' in s:
            print(f'  PARSE [{nm}] slot {key}:', s[:400])
root = em.emit_json(sk, anim_rename={}, extra_animations={})
for nm, a in root['animations'].items():
    for sname, tls in a.get('slots', {}).items():
        if 'windows' in sname:
            print(f'  EMIT [{nm}] {sname}:', json.dumps(tls)[:300])
