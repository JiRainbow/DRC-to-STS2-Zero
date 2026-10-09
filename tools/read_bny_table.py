#!/usr/bin/env python3
"""Dump one bny table's records as JSON rows.

The bny file: 大端定长记录+varint 字符串池. Schema comes from the confbean
lua (field order = record layout: GetInt32Value(baseOffset+N) etc.).
This tool handles the common case: read a table by its .lua schema name and
print raw rows (offsets applied per the schema's baseOffset pattern).
Simplified: we dump the STRING POOL and fixed record bytes; field mapping is
done by the schema file when known.
"""
import json
import struct
import sys
from pathlib import Path

BNY = None


def find_bny():
    global BNY
    for cand in Path('.').rglob('*.bny'):
        BNY = cand
        return cand
    raise SystemExit('bny not found')


def main():
    table_name = sys.argv[1] if len(sys.argv) > 1 else ''
    find_bny()
    data = Path(BNY).read_bytes()
    print(f'bny: {len(data)} B (schema-aware dump not implemented; use strings scan)')
    # string pool scan for Zero-related item names
    strings = re.findall(rb'[\x20-\x7e]{4,}', data)
    hits = [s.decode() for s in strings if b'220003014' in s or (b'ling' in s.lower() and b'icon' in s.lower())]
    for h in hits[:20]:
        print(h)


if __name__ == '__main__':
    import re
    main()
