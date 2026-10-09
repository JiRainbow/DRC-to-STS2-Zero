#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""龙族→STS2 mod 迁移包工具（配合同目录 manifest.json）。

用法（在本目录下运行）：
  python transfer.py --list [--tier 3]        列出各条目与当前实例体积
  python transfer.py --verify [--tier 3]      校验源路径存在性 + 产物 sha256 指纹
  python transfer.py --copy D:\\目标盘\\迁移包 [--tier 1] [--dry]   分级复制
  python transfer.py --copy-flat D:\\项目\\dragonraja3 [--tier 1]   就地瘦身：DR 条目扁平拷入
                                              （ModForge 条目保持原位跳过，路径不变）
  python transfer.py --verify-dest D:\\目标盘\\迁移包 [--tier 3]    校验目标端拷贝（含 sha256）

包布局：<dest>/项目/dragonraja/... 与 <dest>/ModForge/... 保持同级（中文目录名
"项目" 不能改 —— LingChar.csproj 的跨仓相对引用 ..\\..\\..\\项目\\dragonraja\\... 依赖它）。
纯 shutil.copytree 拷贝（不调用任何外部进程）。
"""
import argparse
import hashlib
import json
import re
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAN = json.loads((HERE / 'manifest.json').read_text(encoding='utf-8'))
ROOTS = {
    'DR': Path(MAN['source_roots']['DR']),
    'MF': Path(MAN['source_roots']['MF']),
}
GLOBAL_EXCLUDE = {'__pycache__', '.mimosa', 'desktop.ini', 'Thumbs.db'}
_SAFE_PATH = re.compile(r'^[A-Za-z]:[\\/][^&|;<>^%"\'\r\n]*$|^\\\\[^&|;<>^%"\'\r\n]+$')


def assert_local_path(p: Path) -> None:
    """Reject anything that is not a plain absolute local/UNC filesystem path."""
    if not p.is_absolute() or not _SAFE_PATH.match(str(p)):
        raise SystemExit(f'unsafe path argument: {p!r}')


def src_of(item):
    return ROOTS[item['root']] / item['rel']


def dst_of(root, item):
    return root / item['dst']


def entry_size(p: Path) -> int:
    if p.is_file():
        return p.stat().st_size
    t = 0
    for f in p.rglob('*'):
        try:
            if f.is_file():
                t += f.stat().st_size
        except OSError:
            pass
    return t


def item_sources(item):
    """Concrete source paths for an item (dir -> itself; files -> each entry)."""
    base = src_of(item)
    if item['kind'] == 'files':
        return [base / rel for rel in item['files']]
    return [base]


def filtered_size(p: Path, excludes) -> int:
    """Tree size with GLOBAL_EXCLUDE + path-name excludes applied (mirror of copy)."""
    exc = GLOBAL_EXCLUDE | set(excludes or [])
    if p.is_file():
        return p.stat().st_size
    total = 0
    for f in p.rglob('*'):
        try:
            if f.is_file() and not any(part in exc for part in f.relative_to(p).parts):
                total += f.stat().st_size
        except OSError:
            pass
    return total


def item_size(item) -> int:
    exc = GLOBAL_EXCLUDE | set(item.get('exclude', []))
    return sum(filtered_size(p, exc) for p in item_sources(item) if p.exists())


def fmt(n: float) -> str:
    for unit in ('B', 'K', 'M', 'G'):
        if n < 1024 or unit == 'G':
            return f'{n:.1f}{unit}'
        n /= 1024


def items_at(tier: int, only: str = None):
    return [it for it in MAN['items']
            if it['tier'] <= tier and (not only or only.lower() in it['dst'].lower())]


def cmd_list(tier: int, only: str = None):
    cur = None
    total = 0
    for it in sorted(MAN['items'], key=lambda i: i['tier']):
        if it['tier'] > tier or (only and only.lower() not in it['dst'].lower()):
            continue
        if it['tier'] != cur:
            cur = it['tier']
            print(f"\n=== T{cur}: {MAN['tiers'][str(cur)]} ===")
        s = item_size(it)
        total += s
        tag = 'OK ' if all(p.exists() for p in item_sources(it)) else 'MISS'
        print(f'  [{tag}] T{it["tier"]} {fmt(s):>8}  {it["root"]}/{it["rel"]}  ->  {it["dst"]}')
        if it['kind'] == 'files':
            for rel in it['files']:
                p = src_of(it) / rel
                print(f'          - {rel} {"OK" if p.exists() else "MISSING"}')
    print(f'\nT1..T{tier} 合计 ≈ {fmt(total)}')


def sha256_file(p: Path, chunk=1 << 20) -> str:
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(chunk), b''):
            h.update(b)
    return h.hexdigest()


def check_artifacts(root, only: str = None) -> list:
    """root=None -> verify at SOURCE roots; root=<dest> -> verify under dest layout.

    only: 只校验 dst 含该子串的产物（配合增量校验/增量拷贝）。"""
    errs = []
    for a in MAN['artifacts']:
        if only and only.lower() not in a['dst'].lower():
            continue
        rel = Path(a['dst'])
        if root is None:
            if rel.parts[:2] == ('项目', 'dragonraja'):
                p = ROOTS['DR'] / Path(*rel.parts[2:])
            else:
                p = ROOTS['MF'] / Path(*rel.parts[1:])
        else:
            p = root / rel
        if not p.exists():
            errs.append(f'artifact MISSING: {p}')
            continue
        got = sha256_file(p)
        if got != a['sha256']:
            errs.append(f'sha256 MISMATCH: {p}\n  expect {a["sha256"]}\n  got    {got}')
        else:
            print(f'  artifact OK  {p}  ({fmt(p.stat().st_size)}, sha256 {a["sha256"][:12]}...)')
    return errs


def cmd_verify(tier: int, only: str = None):
    print('== 源路径存在性 ==')
    missing = []
    n = 0
    for it in items_at(tier, only):
        for p in item_sources(it):
            n += 1
            if not p.exists():
                missing.append(p)
                print('  MISSING', p)
    print(f'  {len(missing)} missing of {n} sources')
    print('== 产物 sha256（源端）==')
    errs = check_artifacts(None, only)
    if missing or errs:
        print('\nVERIFY FAILED')
        for e in errs:
            print(' ', e)
        return 1
    print('\nVERIFY OK')
    return 0


def copy_entry(s: Path, d: Path, excludes=(), dry=False) -> int:
    if not s.exists():
        print('  !! MISSING SRC', s)
        return 0
    if dry:
        print(f'  dry: {s} -> {d}')
        return 0
    d.parent.mkdir(parents=True, exist_ok=True)
    if s.is_file():
        shutil.copy2(s, d)
        return s.stat().st_size
    ign = shutil.ignore_patterns(*(GLOBAL_EXCLUDE | set(excludes or [])))
    shutil.copytree(s, d, ignore=ign, dirs_exist_ok=True)
    return filtered_size(s, excludes)


def cmd_copy(dest: Path, tier: int, dry=False, only: str = None):
    assert_local_path(dest)
    if dest.exists() and not dest.is_dir():
        print('dest exists and is not a directory:', dest)
        return 1
    log = []
    t0 = time.time()
    total = 0
    for it in sorted(MAN['items'], key=lambda i: (i['tier'], i['dst'])):
        if it['tier'] > tier or (only and only.lower() not in it['dst'].lower()):
            continue
        print(f"[T{it['tier']}] {it['root']}/{it['rel']} -> {dest / it['dst']}")
        exc = it.get('exclude', [])
        if it['kind'] == 'files':
            base_src = src_of(it)
            base_dst = dst_of(dest, it)
            for rel in it['files']:
                nn = copy_entry(base_src / rel, base_dst / rel, exc, dry)
                total += nn
                log.append(f"{it['root']}/{it['rel']}/{rel} -> {it['dst']}/{rel} ({nn})")
        else:
            nn = copy_entry(src_of(it), dst_of(dest, it), exc, dry)
            total += nn
            log.append(f"{it['root']}/{it['rel']} -> {it['dst']} ({nn})")
    dt = time.time() - t0
    print(f'\ncopied ≈{fmt(total)} in {dt:.1f}s  (dry={dry})')
    if not dry:
        (dest / '_迁移拷贝日志.txt').write_text(
            f'# {MAN["project"]}\ngenerated {MAN["generated"]}  copy {time.strftime("%Y-%m-%d %H:%M:%S")}  tier<={tier}\n'
            + '\n'.join(log) + '\n', encoding='utf-8')
        print('log ->', dest / '_迁移拷贝日志.txt')
    return 0


def flat_dst(dest: Path, item):
    """就地瘦身映射：dst 去掉前缀 项目/dragonraja（DR 条目）。"""
    parts = Path(item['dst']).parts
    if item['root'] == 'DR' and parts[:2] == ('项目', 'dragonraja'):
        return dest.joinpath(*parts[2:])
    raise SystemExit(f'flat mode expects DR dst under 项目/dragonraja: {item["dst"]}')


def cmd_copy_flat(dest: Path, tier: int, dry=False, only: str = None):
    """把 DR 条目按 rel 扁平拷入 dest（就地瘦身用；ModForge 条目原位跳过）。"""
    assert_local_path(dest)
    total = 0
    skipped_mf = 0
    t0 = time.time()
    for it in sorted(MAN['items'], key=lambda i: (i['tier'], i['dst'])):
        if it['tier'] > tier or (only and only.lower() not in it['dst'].lower()):
            continue
        if it['root'] != 'DR':
            skipped_mf += 1
            print(f"[skip] {it['root']}/{it['rel']}（ModForge 保持原位，不参与就地瘦身）")
            continue
        base_src = src_of(it)
        base_dst = flat_dst(dest, it)
        exc = it.get('exclude', [])
        print(f"[T{it['tier']}] {it['rel']} -> {base_dst}")
        if it['kind'] == 'files':
            for rel in it['files']:
                total += copy_entry(base_src / rel, base_dst / rel, exc, dry)
        else:
            total += copy_entry(base_src, base_dst, exc, dry)
    print(f'\ncopied ≈{fmt(total)} in {time.time() - t0:.1f}s  (dry={dry}; MF skipped: {skipped_mf})')
    return 0


def cmd_verify_dest(dest: Path, tier: int, only: str = None):
    assert_local_path(dest)
    print('== 目标端要点校验 ==')
    bad = 0
    for it in items_at(tier, only):
        base = dst_of(dest, it)
        for p in item_sources(it):
            if it['kind'] == 'files':
                rel = p.relative_to(src_of(it))
                q = base / rel
            else:
                q = base
            if not q.exists():
                print('  MISSING', q)
                bad += 1
    print('== 产物 sha256（目标端）==')
    errs = check_artifacts(dest, only)
    if bad or errs:
        print('\nDEST VERIFY FAILED')
        return 1
    print('\nDEST VERIFY OK')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--verify', action='store_true')
    ap.add_argument('--copy', metavar='DEST')
    ap.add_argument('--copy-flat', metavar='DEST')
    ap.add_argument('--verify-dest', metavar='DEST')
    ap.add_argument('--tier', type=int, default=None)
    ap.add_argument('--only', metavar='SUBSTR', help='只处理 dst 含该子串的条目（小规模试跑/增量同步）')
    ap.add_argument('--dry', action='store_true')
    a = ap.parse_args()
    if a.list:
        cmd_list(a.tier or 3, a.only)
    elif a.verify:
        return cmd_verify(a.tier or 3, a.only)
    elif a.copy:
        return cmd_copy(Path(a.copy), a.tier or 1, a.dry, a.only)
    elif a.copy_flat:
        return cmd_copy_flat(Path(a.copy_flat), a.tier or 1, a.dry, a.only)
    elif a.verify_dest:
        return cmd_verify_dest(Path(a.verify_dest), a.tier or 3, a.only)
    else:
        ap.print_help()
    return 0


if __name__ == '__main__':
    sys.exit(main())
