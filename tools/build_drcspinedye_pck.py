"""Build the DRCSpineDye framework pck: per-skin material profiles.

Profile = 4 blend-variant gdshaders + config.json. The ling profile carries
the p215 verbatim port with w_scale=0 (direct draw of the shipped texture;
the framework stays as the mounting point for future lighting passes).

Flow: copy pcksrc/drc_dye into a scratch Godot project, headless --import to
produce .import + ctex products, copy those back into pcksrc, pack.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRW = ROOT / 'sts2_work/DRCSpineDye'
SCRATCH = FRW / 'scratch2'
PCKSRC = FRW / 'pcksrc'
GODOT = Path('D:/Tools/Godot/Godot_v4.7.2-stable_mono_win64_console.exe')

sys.path.insert(0, str(ROOT / 'tools'))
import pck_writer  # noqa: E402


def main():
    has_png = any(PCKSRC.rglob('*.png'))
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True)
    shutil.copytree(PCKSRC / 'drc_dye', SCRATCH / 'drc_dye')
    (SCRATCH / 'project.godot').write_text(
        'config_version=5\n\n[application]\n\nconfig/name="import_scratch"\n', encoding='utf-8')

    if has_png:
        r = subprocess.run([str(GODOT), '--headless', '--path', str(SCRATCH), '--import'],
                           capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            print(r.stdout[-3000:])
            print(r.stderr[-3000:])
            raise SystemExit('godot import failed')

        imp = SCRATCH / '.godot/imported'
        cts = sorted(imp.glob('*.ctex'))
        print('imported:', [c.name for c in cts])

        # copy .import files next to sources and products into pcksrc/.godot/imported
        for src_import in SCRATCH.rglob('*.import'):
            rel = src_import.relative_to(SCRATCH)
            shutil.copy(src_import, PCKSRC / rel)
        (PCKSRC / '.godot/imported').mkdir(parents=True, exist_ok=True)
        for c in cts:
            shutil.copy(c, PCKSRC / '.godot/imported' / c.name)
        # also the .godot/uid_cache.bin style files are not needed; remap lives in .import

    files = []
    for p in sorted(PCKSRC.rglob('*')):
        if not p.is_file():
            continue
        rel = p.relative_to(PCKSRC).as_posix()
        if '.mimosa' in p.parts or '.godot' not in p.parts and not (
                p.suffix in ('.tres', '.gdshader', '.json', '.png', '.import')):
            continue
        files.append((rel, p))
    files = sorted(set(files))
    n, size = pck_writer.build_pck(files, FRW / 'DRCSpineDye.pck')
    print(f'packed {n} files, {size} bytes')
    for rel, _ in files:
        print('  ', rel)


if __name__ == '__main__':
    main()
