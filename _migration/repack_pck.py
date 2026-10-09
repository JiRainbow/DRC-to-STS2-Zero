#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从既有素材树重打一个 mod pck（不经过 Godot 重导入）。

用法: python repack_pck.py <pcksrc_dir> <out.pck>

等价于 tools/build_battle_pck.py / build_lingchar.py 最后的 pack() 步骤：
按路径排序、以 tools/pck_writer.build_pck 打包。用于「素材树未变、只想重新
封包」或「Godot 不在手」的场合；正常重建仍应走各自 build_* 脚本。

迁移后如根目录变化，改下面的 DR_ROOT 常量即可。
"""
import sys
from pathlib import Path

DR_ROOT = Path(r'D:\项目\dragonraja')


def main(pcksrc: str, out: str) -> None:
    sys.path.insert(0, str(DR_ROOT / 'tools'))
    import pck_writer
    src = Path(pcksrc)
    files = [(p.relative_to(src).as_posix(), p)
             for p in sorted(src.rglob('*')) if p.is_file()]
    n, size = pck_writer.build_pck(files, Path(out))
    print(f'packed {n} files, {size} bytes -> {out}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
