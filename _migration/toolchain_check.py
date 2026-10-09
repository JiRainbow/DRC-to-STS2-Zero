#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""工具链完好性检查（就地瘦身 / 迁移后自检）。

用法:
  python _migration/toolchain_check.py [--root DIR]
默认 root = 本文件所在 _migration 目录的上一级（工作树根）。
检查项:
  [1] tools/**/*.py 语法编译（内存 compile，不写盘）
  [2] 关键模块 import（pck_writer / 解析器）
  [3] 脚本内硬编码路径审计：按 manifest 的 T1 集判定"应有却缺"（FAIL）
      与"预期外缺失（T2/T3 未随迁）"（WARN）
  [4] mod PCK 冒烟解析 + 皮肤 pck sha256 基线比对
  [5] 构建关键文件清单抽查
退出码: 0 = 无 FAIL；1 = 有 FAIL
"""
import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument('--root', default=None, help='工作树根（默认取本脚本所在 _migration 的上一级）')
ARGS = ap.parse_args()
ROOT = Path(ARGS.root).resolve() if ARGS.root else Path(__file__).resolve().parent.parent
TOOLS = ROOT / 'tools'

fails = []
warns = []


def ok(msg):
    print('PASS  ' + msg)


def record(kind, msg):
    (fails if kind == 'FAIL' else warns).append(msg)
    print(f'{kind}  {msg}')


print(f'== 工具链自检  root={ROOT}')

# ---------- [1] tools 语法编译 ----------
SKIP = {'jadx', 'quickbms', '__pycache__', '.mimosa', '.godot', 'node_modules'}
n_compiled = 0
for p in sorted(TOOLS.rglob('*.py')):
    if any(part in SKIP for part in p.parts):
        continue
    txt = None
    for enc in ('utf-8', 'gbk', 'latin-1'):
        try:
            txt = p.read_text(encoding=enc)
            break
        except UnicodeDecodeError:
            continue
    if txt is None:
        record('WARN', f'读取失败 {p}')
        continue
    try:
        compile(txt, str(p), 'exec')
        n_compiled += 1
    except SyntaxError as e:
        record('FAIL', f'语法错误 {p.name}: {e}')
ok(f'[1] tools 语法编译通过 {n_compiled} 个 .py')

# ---------- [2] 关键模块 import ----------
sys.path.insert(0, str(TOOLS))
for mod, level in (('pck_writer', 'FAIL'), ('godot_pck', 'WARN'),
                   ('spine41_parse', 'WARN'), ('spine42_emit', 'WARN'),
                   ('az_spine_extract', 'WARN'), ('pck_list', 'WARN')):
    try:
        __import__(mod)
        ok(f'[2] import {mod}')
    except Exception as e:
        record(level, f'import {mod}: {e!r}')

# ---------- [3] 硬编码路径审计 ----------
man = None
mf = ROOT / '_migration' / 'manifest.json'
if mf.exists():
    man = json.loads(mf.read_text(encoding='utf-8'))
prefixes, exacts = set(), set()
if man:
    for it in man['items']:
        if it['tier'] != 1 or it['root'] != 'DR':
            continue
        base = it['rel']
        if it['kind'] == 'dir':
            if base != '.':
                prefixes.add(base)
        elif it['kind'] == 'file':
            exacts.add(base)
        else:
            for f in it['files']:
                exacts.add(f if base == '.' else f'{base}/{f}')


def covered(rel: str) -> bool:
    rel = rel.replace('\\', '/').strip('/')
    if rel in exacts:
        return True
    return any(rel == p or rel.startswith(p + '/') for p in prefixes)


DR_RE = re.compile(r'^[Dd]:[\\/]项目[\\/]dragonraja[\\/]?')
MF_RE = re.compile(r'^[Dd]:[\\/]ModForge[\\/]?')
ENV_RE = re.compile(r'^[Dd]:[\\/](Tools|Program)[\\/]?|steam', re.I)
scripts = sorted(TOOLS.glob('*.py'))
bl = Path(r'D:\ModForge\spikes\LingChar\build_lingchar.py')
if bl.exists():
    scripts.append(bl)

lit_re = re.compile(r"[A-Za-z]:[\\/][^\s'\"\)\]]+")
seen = set()
n_checked = n_miss_critical = n_miss_expected = 0
for sp in scripts:
    try:
        txt = sp.read_text(encoding='utf-8', errors='replace')
    except OSError:
        continue
    for m in lit_re.findall(txt):
        lit = re.sub(r'\\{2,}', r'\\', m).rstrip('\\/')
        if lit in seen:
            continue
        seen.add(lit)
        if DR_RE.match(lit):
            rel = DR_RE.sub('', lit).replace('\\', '/')
            tgt = ROOT / rel
            n_checked += 1
            if not tgt.exists():
                if covered(rel):
                    n_miss_critical += 1
                    record('FAIL', f'[{sp.name}] T1 内应有却缺失: {rel}')
                else:
                    n_miss_expected += 1
                    record('WARN', f'[{sp.name}] 预期外缺失（T2/T3 未随迁）: {rel}')
        elif MF_RE.match(lit):
            n_checked += 1
            if not Path(lit).exists():
                record('FAIL', f'[{sp.name}] ModForge 引用缺失: {lit}')
        elif ENV_RE.search(lit):
            if not Path(lit).exists():
                # 可能是被空格截断的前缀片段（如 "D:/Program" ← "D:/Program Files (x86)/..."）：
                # 父目录里存在以该片段开头的真实项则视为截断伪影，不计警告
                parent = Path(lit).parent
                frag = Path(lit).name
                truncated = False
                if parent.exists() and frag:
                    try:
                        truncated = any(parent.glob(frag + '*'))
                    except OSError:
                        truncated = False
                if not truncated:
                    record('WARN', f'[{sp.name}] 环境路径不存在: {lit}')
ok(f'[3] 路径审计: {n_checked} 条引用（T1 硬缺={n_miss_critical}，预期外={n_miss_expected}）')

# ---------- [4] PCK 冒烟 ----------
def pck_count(p: Path) -> int:
    d = p.read_bytes()
    if d[:4] != b'GDPC':
        raise ValueError('非 GDPC 头')
    dir_off = struct.unpack_from('<q', d, 0x20)[0]
    return struct.unpack_from('<I', d, dir_off)[0]


SKIN_SHA = '7f751f119db9308d92095974175cc9a21a19b9de3a0ad79c8765177d113bc1ed'
sk = ROOT / 'sts2_work' / 'LingSilentSkin_battle' / 'LingSilentSkin.pck'
if sk.exists():
    try:
        ok(f'[4] 皮肤 pck 解析 {pck_count(sk)} 条')
    except Exception as e:
        record('FAIL', f'皮肤 pck 解析失败: {e!r}')
    h = hashlib.sha256(sk.read_bytes()).hexdigest()
    if h == SKIN_SHA:
        ok('[4] 皮肤 pck sha256 与迁移基线一致')
    else:
        record('FAIL', f'皮肤 pck sha256 不符: {h}')
else:
    record('WARN', '皮肤 pck 不存在（尚未构建过）')

game_mods = Path(r'D:/Program Files (x86)/Steam/steamapps/common/Slay the Spire 2/Mods')
for rel in ('LingChar/LingChar.pck', 'LingSilentSkin/LingSilentSkin.pck'):
    p = game_mods / rel
    if p.exists():
        try:
            ok(f'[4] 游戏侧 {rel} 解析 {pck_count(p)} 条')
        except Exception as e:
            record('WARN', f'游戏侧 {rel} 解析失败: {e!r}')
    else:
        record('WARN', f'游戏侧 {rel} 不存在（游戏未装/未装该 mod）')

# ---------- [5] 构建关键文件抽查 ----------
critical = [
    'tools/pck_writer.py',
    'tools/spine41_parse.py',
    'tools/spine42_emit.py',
    'tools/build_battle_pck.py',
    'tools/build_cast_rework.py',
    'tools/build_pdling_select.py',
    'sts2_work/LingSilentSkin_battle/pcksrc/ling/animations/characters/silent/ling.json',
    'sts2_work/LingSilentSkin_battle/pcksrc/animations/character_select/silent/entry_player.gd',
    'sts2_work/LingSilentSkin_battle/pcksrc/scenes/screens/char_select/char_select_bg_silent.tscn',
    'sts2_work/LingSilentSkin_mod/_pcksrc/ling/animations/characters/silent/ling.json',
    'sts2_work/pck_silent_scenes/scenes/creature_visuals/silent.tscn',
    'sts2_work/DRCSpineDye/dll/DyeFramework.cs',
    'sts2_work/DRCSpineDye/pcksrc/drc_dye/profiles/ling/animations/characters/silent/config.json',
    'render_work/battle_capture/captured_tex827.png',
    'render_work/lingUI/启灵卡_镜瞳_未觉醒_大图.png',
    'render_work/pd_ling2/s_plotdrawing',
    'render_work/mirror_shaders/u066941_FS.glsl',
    'unpacked/iguf_out/chr_ling005.png',
    'unpacked/spinemats',
    'unpacked/res_models/characters/ling001',
    'resources/_索引.json',
    'com.zulong.drc.gw/files/ingameupdate/iguf_00.dat',
    '_migration/manifest.json',
]
n_crit = 0
for rel in critical:
    if (ROOT / rel).exists():
        n_crit += 1
    else:
        record('FAIL', f'[5] 关键文件缺失: {rel}')
ok(f'[5] 关键文件抽查 {n_crit}/{len(critical)}')

# ---------- 汇总 ----------
print()
print(f'== 汇总: FAIL={len(fails)}  WARN={len(warns)}')
for m in fails:
    print('  FAIL', m)
for m in warns:
    print('  WARN', m)
sys.exit(1 if fails else 0)
