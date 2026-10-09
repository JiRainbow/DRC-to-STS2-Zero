#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""完成"就地瘦身"改名三步舞（幂等，可由计划任务 DRCSwap 每分钟调用，也可手动）。

入口约定：计划任务的执行体必须是**两棵树之外**的稳定文件
（D:\\项目\\drc_swap.cmd），它再调用本脚本。若用位于 dragonraja3 内的批处理
直接做任务动作，cmd 持有批处理文件的句柄会让 dragonraja3→dragonraja 的
改名失败（WinError 32）并形成死循环——本脚本自身由 pythonw 在启动时整读
载入、随即关闭句柄，所以放在被改名树内是安全的。

目标终态：
  D:\\项目\\dragonraja    = 瘦身树（T1 保留集，本次已拷入 dragonraja3）
  D:\\项目\\dragonraja2   = 瘦身前完整旧树（伪删除备份，验证满意后可整体删除）

退出码：0=已完成/已清理；2=被占用，等待；3=异常（会写日志）。
"""
import contextlib
import hashlib
import io
import runpy
import sys
import time
from pathlib import Path

BASE = Path(r'D:\项目')
OLD = BASE / 'dragonraja'    # 现：完整旧树 → 终态：瘦身树
MID = BASE / 'dragonraja2'   # 终态：完整旧树备份
NEW = BASE / 'dragonraja3'   # 现：瘦身树（T1 已就位并校验）

STATUS = NEW / '_migration' / '_swap_status.txt'      # 状态文件（NEW 改名后随之迁移）
LOG = NEW / '_migration' / '_swap_log.txt'            # 状态变化日志
SKIN_PCK_REL = 'sts2_work/LingSilentSkin_battle/LingSilentSkin.pck'
SKIN_SHA = '7f751f119db9308d92095974175cc9a21a19b9de3a0ad79c8765177d113bc1ed'
PRECHECK = [
    'tools/pck_writer.py',
    'tools/build_battle_pck.py',
    'sts2_work/LingSilentSkin_battle/LingSilentSkin.pck',
    'sts2_work/LingSilentSkin_battle/pcksrc/ling/animations/characters/silent/ling.json',
    'sts2_work/pck_silent_scenes/scenes/creature_visuals/silent.tscn',
    'sts2_work/DRCSpineDye/dll/DyeFramework.cs',
    'resources/_索引.json',
    'render_work/battle_capture/captured_tex827.png',
    'unpacked/res_models/characters/ling001',
    '_migration/manifest.json',
    '_migration/toolchain_check.py',
]

_state_last = None


def now() -> str:
    return time.strftime('%Y-%m-%d %H:%M:%S')


def status(state: str, detail: str = '') -> None:
    """写状态文件；状态未变化时只更新时间戳，不追加日志。
    改名前后两棵树路径都尝试（NEW 改名后即消失，回落到 OLD）。"""
    global _state_last
    line = f'{now()} state={state} {detail}\n'
    for base in (NEW, OLD):
        try:
            p = base / '_migration' / '_swap_status.txt'
            if not p.parent.exists():
                continue
            p.write_text(line, encoding='utf-8')
        except OSError:
            pass
    if state != _state_last:
        _state_last = state
        for base in (NEW, OLD):
            try:
                p = base / '_migration' / '_swap_log.txt'
                if not p.parent.exists():
                    continue
                with open(p, 'a', encoding='utf-8') as fh:
                    fh.write(line)
            except OSError:
                pass
    print(line.rstrip())


def is_slim(p: Path) -> bool:
    """瘦身树特征：带迁移工具、且没有 T2/T3 的 unpacked/reversed 研究库。"""
    return (p / '_migration' / 'toolchain_check.py').exists() and \
        not (p / 'unpacked' / 'reversed').exists()


def try_rename(a: Path, b: Path) -> str:
    """返回 'ok' | 'locked' | 'error:<msg>'。"""
    try:
        a.rename(b)
        return 'ok'
    except OSError as e:
        code = getattr(e, 'winerror', None)
        if code in (5, 32, 33) or getattr(e, 'errno', None) in (11, 13, 16, 26):
            return 'locked'
        return f'error:{e!r}'


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, 'rb') as fh:
        for b in iter(lambda: fh.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def precheck(tree: Path) -> str:
    missing = [rel for rel in PRECHECK if not (tree / rel).exists()]
    if missing:
        return f'missing:{missing[:4]}'
    try:
        got = sha256_file(tree / SKIN_PCK_REL)
    except OSError as e:
        return f'skin pck unreadable: {e!r}'
    if got != SKIN_SHA:
        return f'skin pck sha mismatch: {got[:16]}...'
    return ''


def done(kind: str) -> int:
    note = MID / '!_瘦身前完整备份_可删除.txt'
    if MID.exists() and not note.exists():
        note.write_text(
            '这是 2026-10-09 就地瘦身前的完整旧树（伪删除备份）。\n'
            '内容 = T1 保留集 + T2 研究库（unpacked/reversed、res_* 全集等）'
            '+ T3 残留（apk 解压、iguf 中间物、render_work 实验目录）。\n'
            '新工作树 = D:\\项目\\dragonraja（T1 瘦身树，已通过全量 sha256 对拷校验）。\n'
            '确认新树工作正常后，本目录可整体删除以释放空间。\n', encoding='utf-8')
    report = ''
    checker = OLD / '_migration' / 'toolchain_check.py'
    if checker.exists():
        buf = io.StringIO()
        argv_save = sys.argv[:]
        try:
            sys.argv = ['toolchain_check.py', '--root', str(OLD)]
            with contextlib.redirect_stdout(buf):
                try:
                    runpy.run_path(str(checker), run_name='__main__')
                except SystemExit:
                    pass
        except Exception as e:  # noqa: BLE001
            buf.write(f'toolchain_check crashed: {e!r}\n')
        finally:
            sys.argv = argv_save
        report = buf.getvalue()
    else:
        report = '(toolchain_check.py 不存在)\n'
    rep_path = OLD / '_migration' / 'swap_report.txt'
    try:
        rep_path.write_text(
            f'{now()} 就地瘦身改名完成（{kind}）\n'
            f'终态：dragonraja=瘦身树  dragonraja2=完整旧备份\n\n{report}',
            encoding='utf-8')
    except OSError:
        pass
    status('done', f'{kind}; report={rep_path}')
    return 0


def main() -> int:
    o, m, n = OLD.exists(), MID.exists(), NEW.exists()

    # 终态 / 已手动完成：新树已在 OLD，备份已在 MID
    if o and m and not n:
        if is_slim(OLD):
            return done('already-done')
        status('odd', 'MID exists but OLD is not the slim tree — 需人工检查')
        return 3

    # 旧树已被删：直接把新树顶上
    if not o and not m and n:
        if not is_slim(NEW):
            status('error', 'NEW 不是瘦身树，拒绝改名')
            return 3
        r = try_rename(NEW, OLD)
        if r == 'locked':
            status('locked', 'NEW→OLD blocked')
            return 2
        return done('old-tree-gone') if r == 'ok' else (status('error', r) or 3)

    # 上轮完成 OLD→MID、NEW→OLD 未完成：续跑
    if not o and m and n:
        r = try_rename(NEW, OLD)
        if r == 'locked':
            status('locked', 'resume NEW→OLD blocked')
            return 2
        return done('resumed') if r == 'ok' else (status('error', r) or 3)

    # 正常首跑：OLD 完整树 + NEW 瘦身树，MID 不存在
    if o and not m and n:
        if not is_slim(NEW):
            status('error', 'NEW 不是瘦身树，拒绝改名')
            return 3
        problem = precheck(NEW)
        if problem:
            status('precheck-fail', problem)
            return 3
        r1 = try_rename(OLD, MID)
        if r1 == 'locked':
            status('locked', 'OLD→MID blocked (ZCode 占用中)')
            return 2
        if r1 != 'ok':
            status('error', f'OLD→MID: {r1}')
            return 3
        r2 = try_rename(NEW, OLD)
        if r2 == 'ok':
            return done('swap-complete')
        rb = try_rename(MID, OLD)
        status('error', f'NEW→OLD {r2}; rollback={rb}')
        return 3

    status('odd', f'exists o={o} m={m} n={n}')
    return 3


if __name__ == '__main__':
    sys.exit(main())
