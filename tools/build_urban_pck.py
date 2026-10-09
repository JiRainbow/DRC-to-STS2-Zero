#!/usr/bin/env python3
"""Build LingUrbanSkin pck: urban dragon-dialect (chr_ling005) assets with the
channel-order-fixed texture decode (unpacked/iguf_out/chr_ling005.png, iguf
extraction verified against the captured ling001 baseline). Page keeps the
Chr_ling001.png name to reuse the silent import chain (same ctex hash).
"""
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OLD = ROOT / 'sts2_work/LingUrbanSkin_mod/_pcksrc'
OUTDIR = ROOT / 'sts2_work/LingUrbanSkin_mod/LingUrbanSkin'
SCRATCH = ROOT / 'sts2_work/LingUrbanSkin_mod/scratch_imp'
PCKSRC = SCRATCH / 'pcksrc'
BASELINE_PNG = ROOT / 'unpacked/iguf_out/chr_ling005.png'
GODOT = Path('D:/Tools/Godot/Godot_v4.7.2-stable_mono_win64_console.exe')


def run_import():
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    src = SCRATCH / 'ling/animations/characters/silent'
    src.mkdir(parents=True)
    (SCRATCH / 'project.godot').write_text(
        'config_version=5\n\n[application]\n\nconfig/name="import_scratch"\n', encoding='utf-8')
    shutil.copy(BASELINE_PNG, src / 'Chr_ling001.png')
    r = subprocess.run([str(GODOT), '--headless', '--path', str(SCRATCH), '--import'],
                       capture_output=True, text=True, timeout=300)
    print(r.stdout[-400:], r.stderr[-400:])
    imp = SCRATCH / '.godot/imported'
    cts = sorted(imp.glob('*.ctex')) if imp.exists() else []
    print('imported:', [c.name for c in cts])
    assert len(cts) == 1, 'expected 1 ctex product'
    return cts[0]


def assemble(ctex):
    if PCKSRC.exists():
        shutil.rmtree(PCKSRC)
    PCKSRC.mkdir(parents=True)
    (PCKSRC / '.godot/imported').mkdir(parents=True)
    for rel in ('animations/characters/silent/silent_skel_data.tres',
                'ling/animations/characters/silent/ling.json',
                'ling/animations/characters/silent/ling.json.import',
                'ling/animations/characters/silent/ling.atlas',
                'ling/animations/characters/silent/ling.atlas.import',
                'ling/animations/characters/silent/Chr_ling001.png.import'):
        (PCKSRC / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(OLD / rel, PCKSRC / rel)
    for f in (OLD / '.godot/imported').iterdir():
        if f.suffix in ('.spjson', '.spatlas'):
            shutil.copy(f, PCKSRC / '.godot/imported' / f.name)
    shutil.copy(ctex, PCKSRC / '.godot/imported' / ctex.name)
    shutil.copy(BASELINE_PNG, PCKSRC / 'ling/animations/characters/silent/Chr_ling001.png')
    # regenerate the .spjson product from the CURRENT ling.json (the game loads
    # the imported product; product name = md5 of the source path w/o res:// --
    # md5 is Godot's own remap naming, not a security primitive)
    src = (PCKSRC / 'ling/animations/characters/silent/ling.json').read_bytes()
    name = 'ling.json-' + hashlib.md5(b'ling/animations/characters/silent/ling.json').hexdigest() + '.spjson'
    (PCKSRC / '.godot/imported' / name).write_bytes(src)
    print('spjson regenerated:', name, len(src), 'B')


def pack():
    sys.path.insert(0, str(ROOT / 'tools'))
    import pck_writer
    files = []
    for p in sorted(PCKSRC.rglob('*')):
        if p.is_file():
            files.append((p.relative_to(PCKSRC).as_posix(), p))
    OUTDIR.mkdir(parents=True, exist_ok=True)
    n, size = pck_writer.build_pck(files, OUTDIR / 'LingUrbanSkin.pck')
    print(f'packed {n} files, {size} bytes')
    for rel, _ in files:
        print('  ', rel)


if __name__ == '__main__':
    imp = run_import()
    assemble(imp)
    pack()
