"""Batch-reverse ALL shader sources from the Zulong shadercode package (v2).

Every file in unpacked/res_shadercode/shadercode-afile-glsl_es3_1_android/00..ff/
is [u32 unzipped][u8 ?][u32 zipped][LZ4 raw block]. The payload is an LSLGSP
container: magic "LSLGSP" + reflection metadata (vertex input semantics,
binding slots) + one complete GLSL ES 3.1 source, ending with "}\n\n\x00".

Output (all under unpacked/reversed/):
  shaders/unique/uNNNNNN.glsl   one file per byte-identical inner GLSL source
  shaders/shaders_index.csv     per original file: kind, unique id, size, semantics, samplers, uniform arrays
"""
import csv
import hashlib
import io
import re
import time
from pathlib import Path

import lz4.block

ROOT = Path("unpacked/res_shadercode/shadercode-afile-glsl_es3_1_android").resolve()
OUT = Path("unpacked/reversed/shaders").resolve()
OUT_UNIQUE = OUT / "unique"
OUT.mkdir(parents=True, exist_ok=True)
OUT_UNIQUE.mkdir(exist_ok=True)

RE_UNIARR = re.compile(r"uniform \w+ (\w+)\[(\d+)\];")
RE_SAMP = re.compile(r"uniform \w+ sampler2D (\w+);")
RE_IDENT = re.compile(r"[a-zA-Z_][a-zA-Z0-9_]{4,}")
SAFE_SUB = re.compile(r"^[0-9a-f]{2}$")
SAFE_FN = re.compile(r"^[A-Za-z0-9_.\-]+$")
SAFE_OUT = re.compile(r"^u\d{6}\.glsl$")


def out_file(name: str) -> Path:
    if not SAFE_OUT.match(name):
        raise ValueError(f"unsafe out name: {name}")
    p = (OUT_UNIQUE / name).resolve()
    if p.parent != OUT_UNIQUE:
        raise ValueError(f"escaped out dir: {p}")
    return p


def src_file(subname: str, fn: str) -> Path:
    if not SAFE_SUB.match(subname) or not SAFE_FN.match(fn):
        raise ValueError(f"unsafe name: {subname}/{fn}")
    p = (ROOT / subname / fn).resolve()
    if p.parent != ROOT / subname:
        raise ValueError(f"escaped root: {p}")
    return p


def extract_lslgsp(buf: bytes):
    """Return (glsl_source, semantics_list) from an LSLGSP payload."""
    if not buf.startswith(b"LSLGSP"):
        return buf, []
    v = buf.find(b"#version")
    if v < 0:
        return buf, []
    header = buf[:v]
    sems = []
    seen = set()
    for m in RE_IDENT.finditer(header.decode("latin-1")):
        s = m.group(0)
        if s not in seen and (s.startswith("in_") or s.startswith("out_")):
            seen.add(s)
            sems.append(s)
    end = buf.rfind(b"}\n\n\x00")
    if end < 0:
        end = buf.rfind(b"}\n")
        src = buf[v:end + 2] if end >= 0 else buf[v:]
    else:
        src = buf[v:end + 3]
    return src, sems


files = []
for sub in ROOT.iterdir():          # only the fixed 00..ff subdirs of ROOT
    if sub.is_dir() and SAFE_SUB.match(sub.name):
        for p in sorted(sub.iterdir()):
            if p.is_file() and SAFE_FN.match(p.name):
                files.append((sub.name, p.name))
print(f"shader files: {len(files)}", flush=True)

canon = {}          # sha256 prefix -> unique id
kinds = {}
rows = []
t0 = time.time()
n_bad = 0
for i, (subname, fn) in enumerate(files):
    raw = src_file(subname, fn).read_bytes()
    payload = None
    if len(raw) > 9:
        try:
            payload = lz4.block.decompress(raw[9:], uncompressed_size=2_000_000)
        except Exception:
            payload = None
    rel = f"res_shadercode/shadercode-afile-glsl_es3_1_android/{subname}/{fn}"
    if payload is None:
        n_bad += 1
        rows.append([rel, "", "DECOMP_FAIL", 0, "", "", ""])
        continue
    src, sems = extract_lslgsp(payload)
    if b"gl_Position" in src:
        kind = "VS"
    elif b"out_Target0" in src or b"gl_FragColor" in src or b"gl_FragData" in src:
        kind = "FS"
    else:
        kind = "OTHER"
    h = hashlib.sha256(src).hexdigest()[:16]
    if h not in canon:
        uid = f"u{len(canon):06d}"
        out_file(f"{uid}.glsl").write_bytes(src)
        canon[h] = uid
        kinds[h] = kind
    uid = canon[h]
    txt = src.decode("utf-8", "replace")
    texs = ",".join(RE_SAMP.findall(txt))
    unis = ",".join(f"{n}[{d}]" for n, d in RE_UNIARR.findall(txt))
    rows.append([rel, uid, kind, len(src), ";".join(sems[:16]), texs, unis])
    if (i + 1) % 20000 == 0:
        el = time.time() - t0
        print(f"{i+1}/{len(files)} unique={len(canon)} bad={n_bad} {el:.0f}s", flush=True)

buf = io.StringIO()
w = csv.writer(buf)
w.writerow(["file", "unique_id", "kind", "bytes", "io_semantics", "samplers", "uniform_arrays"])
w.writerows(rows)
(OUT / "shaders_index.csv").write_text(buf.getvalue(), encoding="utf-8")

from collections import Counter
kc = Counter(kinds.values())
print(f"DONE files={len(files)} unique={len(canon)} bad={n_bad} kinds={dict(kc)} {time.time()-t0:.0f}s", flush=True)
