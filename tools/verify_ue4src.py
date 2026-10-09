"""Verify ue4src chunk integrity against functions_index.csv.

Checks every status=ok row has its `// ==== FUNC addr=0x...` header present in the
referenced chunk file (single pass over all chunks). Writes:
  unpacked/reversed/ue4src/_missing_addrs.txt   ok rows whose header is absent
  unpacked/reversed/ue4src/_verify_report.txt   summary + per-chunk count mismatches
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(r"D:\项目\dragonraja\unpacked\reversed\ue4src")
RE_HDR = re.compile(rb"^// ==== FUNC addr=0x([0-9a-f]+) name=", re.M)

found = set()
chunk_stats = {}
for p in sorted(ROOT.glob("part_*.c")):
    n_before = len(found)
    data = p.read_bytes()
    adds = {m.group(1).decode() for m in RE_HDR.finditer(data)}
    found |= adds
    chunk_stats[p.name] = (len(adds), len(data))
    print(f"{p.name}: {len(adds)} headers, {len(data)}B", file=sys.stderr)

ok_rows = 0
missing = []
per_chunk_expect = {}
bad_rows = []
with (ROOT / "functions_index.csv").open(encoding="utf-8") as f:
    for row in csv.DictReader(f):
        if row["status"] in ("ok", "truncated"):
            ok_rows += 1
            a = row["addr"][2:].lower()          # strip 0x
            if a not in found:
                missing.append(a)
                bad_rows.append(row)
            c = row["chunk"]
            if c:
                per_chunk_expect[c] = per_chunk_expect.get(c, 0) + 1

rep = [f"ok_rows={ok_rows} headers_found={len(found)} missing={len(missing)}"]
mism = [(c, exp, chunk_stats.get(c, (0, 0))[0]) for c, exp in per_chunk_expect.items()
        if chunk_stats.get(c, (0, 0))[0] != exp]
rep.append(f"chunks_with_count_mismatch={len(mism)}")
for c, exp, got in mism[:40]:
    rep.append(f"  {c}: expect={exp} got={got}")

(ROOT / "_missing_addrs.txt").write_text("\n".join(missing) + "\n", encoding="utf-8")
(ROOT / "_verify_report.txt").write_text("\n".join(rep) + "\n", encoding="utf-8")
print("\n".join(rep))
