"""Build queryable indexes over the decompiled Lua source tree.

Outputs (under unpacked/reversed/lua_source/):
  lua_index.csv      per file: lines, functions, requires, decompile status
  lua_functions.csv  every function definition: file, line, kind, name
  lua_requires.csv   every require edge: file, module
  _decompile_fail.txt  files the batch failed on (from java driver log)
"""
import csv
import io
import re
from pathlib import Path

ROOT = Path(r"D:\项目\dragonraja\unpacked\reversed\lua_source").resolve()
OUT = ROOT

RE_FUNC = re.compile(
    r"^(\s*)(local\s+)?function\s+([\w.:\[\]'\"]+)|^(\s*)([\w.\[\]:'\"]+)\s*=\s*function")
RE_REQ = re.compile(r"require\s*\(\s*['\"]([\w./\-]+)['\"]\s*\)|require\s*['\"]([\w./\-]+)['\"]")

func_rows = []
req_rows = []
idx_rows = []
fail_rows = []
n_ok = n_fail = n_missing = 0

fail_log = OUT / "_decompile_fail.txt"
failed = set()
if fail_log.exists():
    for ln in fail_log.read_text(encoding="utf-8", errors="replace").splitlines():
        if ln.startswith("FAIL\t"):
            p = ln.split("\t")[1]
            failed.add(p.replace("\\", "/").split("res_lua/", 1)[-1])

for p in sorted(ROOT.rglob("*.lua")):
    rel = p.relative_to(ROOT).as_posix()
    if rel in failed:
        n_fail += 1
        idx_rows.append([rel, 0, 0, 0, "decompile_fail"])
        continue
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        n_missing += 1
        idx_rows.append([rel, 0, 0, 0, "read_error"])
        continue
    lines = txt.splitlines()
    nf = nr = 0
    for i, L in enumerate(lines, 1):
        m = RE_FUNC.match(L)
        if m:
            nf += 1
            if m.group(3):
                kind = "local function" if m.group(2) else "function"
                name = m.group(3)
            else:
                kind = "assigned"
                name = m.group(5)
            func_rows.append([rel, i, kind, name])
        for mm in RE_REQ.finditer(L):
            nr += 1
            req_rows.append([rel, i, mm.group(1) or mm.group(2)])
    n_ok += 1
    idx_rows.append([rel, len(lines), nf, nr, "ok"])

buf = io.StringIO()
w = csv.writer(buf)
w.writerow(["file", "lines", "functions", "requires", "status"])
w.writerows(idx_rows)
(OUT / "lua_index.csv").write_text(buf.getvalue(), encoding="utf-8")

buf = io.StringIO()
w = csv.writer(buf)
w.writerow(["file", "line", "kind", "name"])
w.writerows(func_rows)
(OUT / "lua_functions.csv").write_text(buf.getvalue(), encoding="utf-8")

buf = io.StringIO()
w = csv.writer(buf)
w.writerow(["file", "line", "module"])
w.writerows(req_rows)
(OUT / "lua_requires.csv").write_text(buf.getvalue(), encoding="utf-8")

print(f"files ok={n_ok} fail={n_fail} read_err={n_missing}")
print(f"functions={len(func_rows)} require_edges={len(req_rows)}")
