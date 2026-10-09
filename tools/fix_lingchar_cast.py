"""Replace the stale silent/mirror ling.json (old cast 0.944s) inside the
installed LingChar.pck with the reworked one from LingSilentSkin, and refresh
the matching .godot/imported spjson products."""
import struct, sys, json

sys.path.insert(0, 'tools')
from pck_writer import build_pck
from check_ling_pcks import list_pck

P = r"D:/Program Files (x86)/Steam/steamapps/common/Slay the Spire 2/mods/LingChar/LingChar.pck"
NEW_JSON = r"sts2_work/LingSilentSkin_mod/_pcksrc/ling/animations/characters/silent/ling.json"

files, d = list_pck(P)
new_json = open(NEW_JSON, 'rb').read()

# 源速版补丁:产品 json 里的 cast 是新切源速版(0.9225s)。LingChar 的两个
# 路径(silent/mirror)与 Silent 同骨架,直接使用同一份。
patch = {}
for name in files:
    if name.endswith('ling/animations/characters/silent/ling.json'):
        patch[name] = new_json
    elif name.endswith('ling/animations/characters/mirror/ling.json'):
        patch[name] = new_json
    elif '.godot/imported/ling.json-' in name and name.endswith('.spjson'):
        patch[name] = new_json

assert patch, 'no ling.json targets found'
out_entries = []
for name, (off, size) in files.items():
    data = patch.get(name, d[off:off + size])
    out_entries.append((name, data))

n, total = build_pck(out_entries, P + '.new')
import shutil
shutil.move(P + '.new', P)
print(f'LingChar.pck rebuilt: {n} files, {total}B; patched: {len(patch)}')
for k in sorted(patch):
    print('  ', k)
