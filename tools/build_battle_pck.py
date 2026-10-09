#!/usr/bin/env python3
"""Build LingSilentSkin pck: 100% raw Dragon Raja assets with the
channel-order-fixed baseline texture (captured_tex827, the in-game uploaded
ASTC decoded - verified byte-identical to the base-package uexp payload).
Rendering = vanilla spine-godot = mobile real-battle look.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OLD = ROOT / 'sts2_work/LingSilentSkin_mod/_pcksrc'
OUTDIR = ROOT / 'sts2_work/LingSilentSkin_battle'
SCRATCH = OUTDIR / 'scratch'
PCKSRC = OUTDIR / 'pcksrc'
BASELINE_PNG = ROOT / 'render_work/battle_capture/captured_tex827.png'
GODOT = Path('D:/Tools/Godot/Godot_v4.7.2-stable_mono_win64_console.exe')


def run_import():
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    src = SCRATCH / 'ling/animations/characters/silent'
    src.mkdir(parents=True)
    (SCRATCH / 'project.godot').write_text(
        'config_version=5\n\n[application]\n\nconfig/name="import_scratch"\n', encoding='utf-8')
    shutil.copy(BASELINE_PNG, src / 'Chr_ling001.png')
    # select-screen立绘 page textures need imported ctex products
    pdsrc = SCRATCH / 'pdling'
    pdsrc.mkdir(parents=True)
    pd_dir = OLD / 'animations/character_select/silent'
    for page in sorted(pd_dir.glob('*page*.png')):
        shutil.copy(page, pdsrc / page.name)
    # UI replacements (user art): select bg, select bar block, in-game avatar
    uisrc = SCRATCH / 'uiart'
    uisrc.mkdir(parents=True)
    UI_MAP = {
        ROOT / 'render_work/lingUI/时装页UI背景_fashion_bg.png': 'character_select_silent_bg.png',
        ROOT / 'render_work/lingUI/零_队伍竖条立绘2.png': 'char_select_silent.png',
        ROOT / 'render_work/lingUI/lingtuanzi.png': 'character_icon_silent.png',
    }
    for srcp, dstn in UI_MAP.items():
        shutil.copy(srcp, uisrc / dstn)
    r = subprocess.run([str(GODOT), '--headless', '--path', str(SCRATCH), '--import'],
                       capture_output=True, text=True, timeout=300)
    print(r.stdout[-1500:], r.stderr[-1500:])
    imp = SCRATCH / '.godot/imported'
    cts = sorted(imp.glob('*.ctex')) if imp.exists() else []
    print('imported:', [c.name for c in cts])
    assert len(cts) == 9, 'expected 9 ctex products (Chr + 5立绘 pages + 3 UI; 影子页已废弃)'
    return cts


def assemble(cts):
    ctex = next(c for c in cts if c.name.startswith('Chr_ling001'))
    pd_cts = [c for c in cts if 'page' in c.name and (c.name.startswith('spd_') or c.name.startswith('pdchar_') or c.name.startswith('pd_ling_page'))]
    UI_TARGETS = {
        'character_select_silent_bg.png': 'animations/character_select/silent/character_select_silent_bg.png',
        'char_select_silent.png': 'images/packed/character_select/char_select_silent.png',
        'character_icon_silent.png': 'images/ui/top_panel/character_icon_silent.png',
    }
    ui_cts = [c for c in cts if c.name.split('-')[0] in UI_TARGETS]
    if PCKSRC.exists():
        shutil.rmtree(PCKSRC)
    PCKSRC.mkdir(parents=True)
    (PCKSRC / 'animations/characters/silent').mkdir(parents=True)
    (PCKSRC / 'ling/animations/characters/silent').mkdir(parents=True)
    (PCKSRC / 'animations/merchant/silent').mkdir(parents=True)
    (PCKSRC / 'animations/rest_site/silent').mkdir(parents=True)
    (PCKSRC / '.godot/imported').mkdir(parents=True)
    shutil.copy(OLD / 'animations/characters/silent/silent_skel_data.tres',
                PCKSRC / 'animations/characters/silent/silent_skel_data.tres')
    # shop scene override: the merchant room instantiates
    # scenes/merchant/characters/silent_merchant.tscn whose skeleton data
    # resource points at the VANILLA silent.skel - redirect it to our rig so
    # the shop shows the skin (relaxed_loop included)
    shutil.copy(OLD / 'animations/merchant/silent/silent_merchant_skel_data.tres',
                PCKSRC / 'animations/merchant/silent/silent_merchant_skel_data.tres')
    # rest site override: the scene plays per-act loops (overgrowth/hive/glory)
    # which we alias to sitloop in ling.json; the tscn is patched (scale x0.8,
    # moved down) so our rig sits on the log
    shutil.copy(OLD / 'animations/rest_site/silent/rest_site_silent_skel_data.tres',
                PCKSRC / 'animations/rest_site/silent/rest_site_silent_skel_data.tres')
    rs_tscn = OLD / 'scenes/rest_site/characters/silent_rest_site.tscn'
    (PCKSRC / 'scenes/rest_site/characters').mkdir(parents=True, exist_ok=True)
    shutil.copy(rs_tscn, PCKSRC / 'scenes/rest_site/characters/silent_rest_site.tscn')
    # character select bg scene override: pd_ling portrait rig positioning
    # (origin at head, extends down) + vanilla hunter particles removed
    cs_tscn = OLD / 'scenes/screens/char_select/char_select_bg_silent.tscn'
    (PCKSRC / 'scenes/screens/char_select').mkdir(parents=True, exist_ok=True)
    shutil.copy(cs_tscn, PCKSRC / 'scenes/screens/char_select/char_select_bg_silent.tscn')
    # character select override: PD_Ling display spine (零的立绘, converted
    # by tools/build_pdling_select.py) - the select screen's NSpineAutoPlayer
    # requires exactly one animation, which the single kept loop satisfies
    sel = OLD / 'animations/character_select/silent'
    (PCKSRC / 'animations/character_select/silent').mkdir(parents=True, exist_ok=True)
    for f in sel.iterdir():
        if not f.is_file():
            continue  # .mimosa 等 hook 状态目录不进 pck
        if f.name.endswith('.bak'):
            continue  # hash 色对照留档,不进 pck
        shutil.copy(f, PCKSRC / 'animations/character_select/silent' / f.name)
    # hand-write the spine import products for pd_ling (the scratch Godot has
    # no spine extension): .spjson/.spatlas products = raw bytes, name =
    # md5(source path w/o res://) -- md5 is Godot's own remap naming, not a
    # security primitive; it must stay md5 to match the engine's scheme
    SEL_SRC = 'animations/character_select/silent'
    imp = SCRATCH / '.godot/imported'

    def write_text(rel, content):
        (PCKSRC / rel).write_text(content, encoding='utf-8', newline='\n')

    json_md5 = hashlib.md5(f'{SEL_SRC}/pd_ling.json'.encode()).hexdigest()
    atlas_md5 = hashlib.md5(f'{SEL_SRC}/pd_ling.atlas'.encode()).hexdigest()
    (PCKSRC / '.godot/imported' / f'pd_ling.json-{json_md5}.spjson').write_bytes(
        (PCKSRC / f'{SEL_SRC}/pd_ling.json').read_bytes())
    # .spatlas is a JSON WRAPPER (source_path + atlas_data + prefixes), NOT
    # the raw atlas text - the raw form fails SpineAtlasResource parsing
    atlas_text = (PCKSRC / f'{SEL_SRC}/pd_ling.atlas').read_text(encoding='utf-8')
    spatlas = {'source_path': f'res://{SEL_SRC}/pd_ling.atlas',
               'atlas_data': atlas_text,
               'normal_texture_prefix': '',
               'specular_texture_prefix': ''}
    (PCKSRC / '.godot/imported' / f'pd_ling.atlas-{atlas_md5}.spatlas').write_bytes(
        json.dumps(spatlas, ensure_ascii=False).encode('utf-8'))
    # NO uid= lines: hand-made uid strings can violate Godot's uid charset
    # (i/l/o/u excluded) and fail validation; loading works by path
    write_text(f'{SEL_SRC}/pd_ling.json.import',
               '[remap]\n\nimporter="spine.skel"\ntype="SpineSkeletonFileResource"\n'
               f'path="res://.godot/imported/pd_ling.json-{json_md5}.spjson"\n')
    write_text(f'{SEL_SRC}/pd_ling.atlas.import',
               '[remap]\n\nimporter="spine.atlas"\ntype="SpineAtlasResource"\n'
               f'path="res://.godot/imported/pd_ling.atlas-{atlas_md5}.spatlas"\n')
    # page textures: ctex products came from the scratch import; .import
    # remaps generated from the Chr_ling001 template (copied below)
    for c in pd_cts:
        # c.name = 'pd_ling_pageN.png-<md5>.ctex' -> source page 'pd_ling_pageN.png'
        page = c.name[: -len('.ctex')].split('-')[0]
        write_text(f'{SEL_SRC}/{page}.import',
                   '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
                   f'path="res://.godot/imported/{c.name}"\n'
                   'metadata={\n"vram_texture": false\n}\n\n[deps]\n\n'
                   f'source_file="res://{SEL_SRC}/{page}"\n'
                   f'dest_files=["res://.godot/imported/{c.name}"]\n\n'
                   '[params]\n\ncompress/mode=0\ncompress/high_quality=false\n'
                   'compress/lossy_quality=0.7\ncompress/uastc_level=0\n'
                   'compress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n'
                   'compress/normal_map=0\ncompress/channel_pack=0\n'
                   'mipmaps/generate=false\nmipmaps/limit=-1\nroughness/mode=0\n'
                   'roughness/src_normal=""\nprocess/fix_alpha_border=true\n'
                   'process/premult_alpha=false\nprocess/normal_map_invert_y=false\n'
                   'process/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\n'
                   'process/size_limit=0\ndetect_3d/compress_to=1\n')
    # UI replacements: ship ctex + .import at the game's source paths
    for c in ui_cts:
        base = c.name.split('-')[0]
        tgt = UI_TARGETS[base]
        (PCKSRC / '.godot/imported' / c.name).write_bytes(c.read_bytes())
        os.makedirs(PCKSRC / os.path.dirname(tgt), exist_ok=True)
        write_text(tgt + '.import',
                   '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
                   f'path="res://.godot/imported/{c.name}"\n'
                   'metadata={\n"vram_texture": false\n}\n\n[deps]\n\n'
                   f'source_file="res://{tgt}"\n'
                   f'dest_files=["res://.godot/imported/{c.name}"]\n\n'
                   '[params]\n\ncompress/mode=0\ncompress/high_quality=false\n'
                   'compress/lossy_quality=0.7\ncompress/uastc_level=0\n'
                   'compress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n'
                   'compress/normal_map=0\ncompress/channel_pack=0\n'
                   'mipmaps/generate=false\nmipmaps/limit=-1\nroughness/mode=0\n'
                   'roughness/src_normal=""\nprocess/fix_alpha_border=true\n'
                   'process/premult_alpha=false\nprocess/normal_map_invert_y=false\n'
                   'process/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\n'
                   'process/size_limit=0\ndetect_3d/compress_to=1\n')
        print('ui override:', tgt, '<-', c.name)
    for name in ('ling.json', 'ling.json.import', 'ling.atlas', 'ling.atlas.import'):
        shutil.copy(OLD / 'ling/animations/characters/silent' / name,
                    PCKSRC / 'ling/animations/characters/silent' / name)
    for f in (OLD / '.godot/imported').iterdir():
        if f.suffix in ('.spjson', '.spatlas'):
            shutil.copy(f, PCKSRC / '.godot/imported' / f.name)
    # regenerate the .spjson product from the CURRENT ling.json (the game loads
    # the imported product; product name = md5 of the source path w/o res:// --
    # md5 is Godot's own remap naming, not a security primitive)
    src_json = (PCKSRC / 'ling/animations/characters/silent/ling.json').read_bytes()
    spjson_name = ('ling.json-'
                   + hashlib.md5(b'ling/animations/characters/silent/ling.json').hexdigest()
                   + '.spjson')
    (PCKSRC / '.godot/imported' / spjson_name).write_bytes(src_json)
    print('spjson regenerated:', spjson_name, len(src_json), 'B')
    shutil.copy(ctex, PCKSRC / '.godot/imported' / ctex.name)
    for c in pd_cts:
        shutil.copy(c, PCKSRC / '.godot/imported' / c.name)
        # ship the .import remap alongside (the atlas references the page
        # names; Godot resolves them through these remaps)
        imp_name = c.name[: -len('.ctex')] + '.import'
        imp_src = SCRATCH / 'pdling' / imp_name
        if imp_src.exists():
            shutil.copy(imp_src, PCKSRC / 'animations/character_select/silent' / imp_name)
    shutil.copy(SCRATCH / 'ling/animations/characters/silent/Chr_ling001.png.import',
                PCKSRC / 'ling/animations/characters/silent/Chr_ling001.png.import')
    shutil.copy(BASELINE_PNG, PCKSRC / 'ling/animations/characters/silent/Chr_ling001.png')


def pack():
    sys.path.insert(0, str(ROOT / 'tools'))
    import pck_writer
    files = []
    for p in sorted(PCKSRC.rglob('*')):
        if p.is_file():
            files.append((p.relative_to(PCKSRC).as_posix(), p))
    n, size = pck_writer.build_pck(files, OUTDIR / 'LingSilentSkin.pck')
    print(f'packed {n} files, {size} bytes')
    for rel, _ in files:
        print('  ', rel)


if __name__ == '__main__':
    OUTDIR.mkdir(exist_ok=True)
    ctex = run_import()
    assemble(ctex)
    pack()
    print('sha256 of texture packed:',
          hashlib.sha256(BASELINE_PNG.read_bytes()).hexdigest())
