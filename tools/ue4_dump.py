#!/usr/bin/env python3
"""Universal Zulong UE4 asset reverse-dumper.

Cracked format (empirically verified this session):
  summary:  magic 0x9E2A83C1 @0, TotalHeaderSize@0x18, FolderName FString@0x1C,
            PackageFlags@0x25, NameCount@0x29, NameOffset@0x2D,
            ExportCount@0x39, ExportOffset@0x3D, ImportCount@0x41, ImportOffset@0x45
  names:    [i32 len][bytes incl NUL][u32 hash]
  imports:  28B entries [ClassPackage FName][ClassName FName][i32 outer][ObjectName FName]
  exports:  stride varies (48..128); core fields: ClassIndex@+0 SuperIndex@+4 TemplateIndex@+8
            OuterIndex@+12 ObjectName@+16 FName, ObjectFlags@+24, SerialSize@+28,
            SerialOffset(rel)@+32, AbsOffset@+36 (= TotalHeaderSize + uexp offset);
            stride auto-detected from the contiguous chain abs[k+1] == abs[k] + size[k]
  props:    tagged stream, terminator = FName "None" (8B); tag = [name FName 8B]
            [type FName 8B][size i32][arridx i32][type-specific]; Struct carries
            [inner FName 8B][hasguid u8][16B guid block always]; Byte carries enum FName;
            Bool carries value u8 in tag; Array payload = [count i32][envelope 49B if
            struct-inner][elements]; element = tagged stream ending at None.

Writes readable dumps for every res_* uasset/uexp pair into unpacked/reversed/properties,
plus materials/instances.csv with all MaterialInstance parameters and census.csv.
"""
import csv
import io
import json
import re
import struct
import sys
import time
from pathlib import Path

from parse_mi_uasset import read_names, fstr

BASE = Path(r"D:\项目\dragonraja\unpacked").resolve()
OUT = Path(r"D:\项目\dragonraja\unpacked\reversed").resolve()
OUT_PROPS = OUT / "properties"
OUT_MATS = OUT / "materials"

PTYPES = {
    "ObjectProperty", "IntProperty", "Int64Property", "UInt32Property", "UInt64Property",
    "Int16Property", "UInt16Property", "Int8Property", "FloatProperty", "DoubleProperty",
    "BoolProperty", "ByteProperty", "NameProperty", "StrProperty", "StructProperty",
    "ArrayProperty", "MapProperty", "SetProperty", "EnumProperty", "InterfaceProperty",
    "GuidProperty", "AssetObjectProperty", "SoftObjectProperty", "SoftObjectPath",
    "DelegateProperty", "MulticastDelegateProperty", "MulticastInlineDelegateProperty",
    "MulticastSparseDelegateProperty", "WeakObjectProperty", "LazyObjectProperty",
    "FieldPathProperty", "TextProperty",
}

RE_SAFE = re.compile(r"^[A-Za-z0-9_.\-/]+$")


class Fail(Exception):
    pass


class R:
    __slots__ = ("b", "off", "end")

    def __init__(self, b, off=0, end=None):
        self.b = b
        self.off = off
        self.end = len(b) if end is None else end

    def need(self, n):
        if self.off + n > self.end:
            raise Fail("eof")

    def raw(self, n):
        self.need(n)
        r = self.b[self.off:self.off + n]
        self.off += n
        return r

    def i32(self):
        self.need(4)
        v = struct.unpack("<i", self.b[self.off:self.off + 4])[0]
        self.off += 4
        return v

    def u32(self):
        self.need(4)
        v = struct.unpack("<I", self.b[self.off:self.off + 4])[0]
        self.off += 4
        return v

    def u8(self):
        self.need(1)
        v = self.b[self.off]
        self.off += 1
        return v

    def f32(self):
        self.need(4)
        v = struct.unpack("<f", self.b[self.off:self.off + 4])[0]
        self.off += 4
        return v

    def f64(self):
        self.need(8)
        v = struct.unpack("<d", self.b[self.off:self.off + 8])[0]
        self.off += 8
        return v

    def fname(self):
        i, n = self.u32(), self.i32()
        return i, n

    def fstring(self):
        s, o = fstr(self.b, self.off)
        if o > self.end:
            raise Fail("fstr overrun")
        self.off = o
        return s


class Ctx:
    def __init__(self, names, imports, exports):
        self.names = names
        self.imports = imports
        self.exports = exports
        self.none_idx = names.index("None") if "None" in names else -1

    def nm(self, i):
        return self.names[i] if 0 <= i < len(self.names) else f"?{i}"


def imp_path(ctx, j, depth=0):
    if depth > 8 or j < 0 or j >= len(ctx.imports):
        return f"imp{j}"
    cp_idx, cp_num, cn_idx, cn_num, outer, on_idx, on_num = ctx.imports[j]
    name = ctx.nm(on_idx)
    if outer == 0:
        return name
    if outer < 0:
        return imp_path(ctx, -outer - 1, depth + 1) + "." + name
    if outer > 0:
        return exp_path(ctx, outer - 1, depth + 1) + "." + name
    return name


def exp_path(ctx, j, depth=0):
    if depth > 8 or j < 0 or j >= len(ctx.exports):
        return f"exp{j}"
    ex = ctx.exports[j]
    outer = ex["outer"]
    name = ctx.nm(ex["nidx"])
    if outer > 0:
        return exp_path(ctx, outer - 1, depth + 1) + "." + name
    if outer < 0:
        return imp_path(ctx, -outer - 1, depth + 1) + "." + name
    return name


def obj_ref(ctx, i):
    if i == 0:
        return "None"
    if i < 0:
        j = -i - 1
        if 0 <= j < len(ctx.imports):
            cp, cn = ctx.nm(ctx.imports[j][0]), ctx.nm(ctx.imports[j][2])
            return f"{cn}'{imp_path(ctx, j)}'"
        return f"imp{j}"
    j = i - 1
    if 0 <= j < len(ctx.exports):
        return f"'{exp_path(ctx, j)}'"
    return f"exp{j}"


def class_name(ctx, cls):
    if cls == 0:
        return "?"
    if cls < 0:
        j = -cls - 1
        if 0 <= j < len(ctx.imports):
            cp, cn = ctx.nm(ctx.imports[j][0]), ctx.nm(ctx.imports[j][2])
            if cn == "Class":
                return imp_path(ctx, j)
            return f"{cn} ({cp})" if cp else cn
        return f"imp{cls}"
    j = cls - 1
    if 0 <= j < len(ctx.exports):
        return ctx.nm(ctx.exports[j]["nidx"])
    return f"exp{cls}"


def parse_struct_payload(r, inner, ctx, lines, ind, size_budget):
    """Render a struct payload best-effort."""
    start = r.off
    if inner in ("Vector", "LinearColor", "Vector4", "Rotator", "Vector2D"):
        n = {"Vector": 3, "LinearColor": 4, "Vector4": 4, "Rotator": 3, "Vector2D": 2}[inner]
        vals = [round(r.f32(), 6) for _ in range(n)]
        lines.append(f"{ind}{inner} = {vals}")
    elif inner == "Color":
        vals = struct.unpack("<4B", r.raw(4))
        lines.append(f"{ind}Color = {vals}")
    elif inner == "Guid":
        lines.append(f"{ind}Guid = {r.raw(16).hex()}")
    else:
        # try tagged member stream first (tagged-serializable UScriptStruct)
        sub = []
        try:
            rr = R(r.b, r.off, min(r.end, start + size_budget))
            n2 = parse_tagged_stream(rr, ctx, sub, ind + "  ")
            if n2 > 0 and rr.off > r.off:
                lines.extend(sub)
                r.off = rr.off
                return
        except Fail:
            pass
        lines.extend(sub) if sub else None
        rem = min(size_budget, r.end - r.off)
        blob = r.raw(rem)
        lines.append(f"{ind}[{inner or 'struct'} {len(blob)}B] {blob[:48].hex(' ')}{'...' if len(blob) > 48 else ''}")


def parse_plain_elems(r, inner, ctx, cnt, ind):
    out = []
    for _ in range(min(cnt, 512)):
        if inner in ("IntProperty", "Int64Property"):
            n = 8 if inner == "Int64Property" else 4
            out.append(str(int.from_bytes(r.raw(n), "little", signed=True)))
        elif inner in ("UInt32Property", "UInt64Property"):
            n = 8 if inner == "UInt64Property" else 4
            out.append(str(int.from_bytes(r.raw(n), "little")))
        elif inner == "DoubleProperty":
            out.append(str(round(r.f64(), 6)))
        elif inner in ("Int16Property", "UInt16Property", "Int8Property"):
            n = {"Int16Property": 2, "UInt16Property": 2, "Int8Property": 1}[inner]
            out.append(str(int.from_bytes(r.raw(n), "little", signed=inner.startswith("Int"))))
        elif inner == "FloatProperty":
            out.append(str(round(r.f32(), 6)))
        elif inner == "NameProperty":
            out.append(ctx.nm(r.u32()))
            r.i32()
        elif inner == "ObjectProperty":
            out.append(obj_ref(ctx, r.i32()))
        elif inner == "StrProperty":
            out.append(repr(r.fstring()))
        elif inner == "ByteProperty":
            out.append(str(r.u8()))
        elif inner == "BoolProperty":
            out.append(str(bool(r.u8())))
        elif inner == "StructProperty":
            sub = []
            parse_struct_payload(r, "", ctx, sub, "", 4096)
            out.append(" ".join(s.strip() for s in sub)[:120])
        elif inner == "GuidProperty":
            out.append(r.raw(16).hex())
        else:
            raise Fail(f"plain elem {inner}")
    return out


def read_tag(r, ctx):
    """Read one FPropertyTag (byte-verified layout). Returns dict or None at terminator.

    [name FName 8B][type FName 8B][size i32][arridx i32]
    + type-specific: Struct/Array -> inner FName; Byte/Enum -> enum FName;
                     Bool -> u8 boolval; Map/Set -> inner FName + value-inner FName
    + [u8 hasguid][16B guid if hasguid]           (universal, all types)
    + [16B guid block ALWAYS for StructProperty]  (zeros when none)
    payload follows.
    """
    start = r.off
    ni, _ = r.fname()
    if ni == ctx.none_idx:
        return None
    if ni >= len(ctx.names) or ni < 0:
        raise Fail(f"name idx {ni}")
    ti, _ = r.fname()
    if ti >= len(ctx.names) or ti < 0:
        raise Fail(f"type idx {ti}")
    typ = ctx.nm(ti)
    if typ not in PTYPES:
        raise Fail(f"type {typ}")
    size = r.i32()
    arridx = r.i32()
    if size < 0 or size > (r.end - r.off) + 64:
        raise Fail(f"size {size}")
    tag = {"name": ctx.nm(ni), "type": typ, "size": size, "arridx": arridx, "start": start}
    if typ in ("StructProperty", "ArrayProperty"):
        ii, _ = r.fname()
        tag["inner"] = ctx.nm(ii) if 0 <= ii < len(ctx.names) else f"?{ii}"
    elif typ in ("MapProperty", "SetProperty"):
        ii, _ = r.fname()
        tag["inner"] = ctx.nm(ii) if 0 <= ii < len(ctx.names) else f"?{ii}"
        vi, _ = r.fname()
        tag["vinner"] = ctx.nm(vi) if 0 <= vi < len(ctx.names) else f"?{vi}"
    elif typ == "ByteProperty" or typ == "EnumProperty":
        ei, _ = r.fname()
        tag["enum"] = ctx.nm(ei) if 0 <= ei < len(ctx.names) else ""
    elif typ == "BoolProperty":
        tag["boolval"] = r.u8()
    if r.u8():
        r.raw(16)
    if typ == "StructProperty":
        r.raw(16)
    return tag


def parse_tagged_stream(r, ctx, lines, ind="  "):
    """Parse tagged properties until None terminator. Returns count."""
    cnt = 0
    while True:
        if r.off + 8 > r.end:
            raise Fail("no terminator")
        tag = read_tag(r, ctx)
        if tag is None:
            return cnt
        cnt += 1
        name, typ, size = tag["name"], tag["type"], tag["size"]
        ps = r.off
        try:
            emit_property(r, ctx, tag, lines, ind)
        except Fail:
            r.off = ps + size
            lines.append(f"{ind}{name} ({typ}, {size}B) <unparsed>")
            continue
        consumed = r.off - ps
        if consumed != size:
            lines.append(f"{ind}{name} ({typ}) size mismatch: used {consumed} of {size}B")
            r.off = ps + size


def emit_property(r, ctx, tag, lines, ind):
    name, typ, size = tag["name"], tag["type"], tag["size"]
    if typ == "FloatProperty":
        lines.append(f"{ind}{name} (Float) = {round(r.f32(), 6)}")
    elif typ == "DoubleProperty":
        lines.append(f"{ind}{name} (Double) = {round(r.f64(), 6)}")
    elif typ in ("IntProperty", "Int64Property"):
        n = 8 if typ == "Int64Property" else 4
        v = int.from_bytes(r.raw(n), "little", signed=True)
        lines.append(f"{ind}{name} ({typ}) = {v}")
    elif typ in ("UInt32Property", "UInt64Property", "Int16Property", "UInt16Property", "Int8Property"):
        n = {"UInt32Property": 4, "UInt64Property": 8, "Int16Property": 2, "UInt16Property": 2, "Int8Property": 1}[typ]
        v = int.from_bytes(r.raw(n), "little", signed=typ.startswith("Int"))
        lines.append(f"{ind}{name} ({typ}) = {v}")
    elif typ == "BoolProperty":
        lines.append(f"{ind}{name} (Bool) = {bool(tag.get('boolval'))}")
    elif typ == "ByteProperty":
        if size == 8:
            v, _ = r.fname()
            lines.append(f"{ind}{name} (ByteVal{',' + tag.get('enum', '') if tag.get('enum') else ''}) = {ctx.nm(v)}")
        else:
            blob = r.raw(size)
            lines.append(f"{ind}{name} (Byte[{size}]{',' + tag.get('enum', '') if tag.get('enum') else ''}) = {blob[:32].hex(' ')}")
    elif typ == "EnumProperty":
        v, _ = r.fname()
        lines.append(f"{ind}{name} (Enum{',' + tag.get('enum', '')}) = {ctx.nm(v)}")
    elif typ == "NameProperty":
        v, n = r.fname()
        lines.append(f"{ind}{name} (Name) = {ctx.nm(v)}")
    elif typ in ("ObjectProperty", "AssetObjectProperty", "SoftObjectProperty", "WeakObjectProperty", "LazyObjectProperty", "InterfaceProperty"):
        v = r.i32()
        if typ == "InterfaceProperty":
            r.fname()
        lines.append(f"{ind}{name} ({typ}) = {obj_ref(ctx, v)}")
    elif typ == "GuidProperty":
        lines.append(f"{ind}{name} (Guid) = {r.raw(16).hex()}")
    elif typ == "StrProperty":
        lines.append(f"{ind}{name} (Str) = {r.fstring()!r}")
    elif typ == "TextProperty":
        blob = r.raw(size)
        lines.append(f"{ind}{name} (Text {size}B) {blob[:40].hex(' ')}")
    elif typ == "StructProperty":
        lines.append(f"{ind}{name} (Struct:{tag['inner']})")
        parse_struct_payload(r, tag["inner"], ctx, lines, ind + "  ", size)
    elif typ == "ArrayProperty":
        inner = tag["inner"]
        cnt = r.i32()
        lines.append(f"{ind}{name} (Array<{inner}> count={cnt})")
        if cnt <= 0:
            return
        if inner == "StructProperty":
            # envelope: 33B tag + 16B guid (empirical); validate type slot first
            good = False
            if r.off + 49 <= r.end:
                tslot = struct.unpack("<I", r.b[r.off + 8:r.off + 12])[0]
                good = (tslot < len(ctx.names) and ctx.nm(tslot) == "StructProperty")
            if good:
                r.raw(49)
                for k in range(min(cnt, 512)):
                    sub = []
                    parse_tagged_stream(r, ctx, sub, ind + "  ")
                    lines.append(f"{ind}  [{k}] " + " | ".join(s.strip() for s in sub)[:220])
            else:
                r.raw(max(0, min(size - 4, r.end - r.off)))
                lines.append(f"{ind}  <raw array payload {size - 4}B>")
        else:
            vals = parse_plain_elems(r, inner, ctx, cnt, ind)
            for k, v in enumerate(vals[:24]):
                lines.append(f"{ind}  [{k}] {v}")
            if len(vals) > 24:
                lines.append(f"{ind}  ... {len(vals) - 24} more")
    elif typ in ("MapProperty", "SetProperty"):
        cnt = r.i32()
        blob = r.raw(max(0, min(size - 4, r.end - r.off)))
        lines.append(f"{ind}{name} ({typ} count={cnt}, {len(blob)}B) {blob[:40].hex(' ')}")
    elif typ in ("DelegateProperty",):
        o = r.i32()
        fn, fnn = r.fname()
        lines.append(f"{ind}{name} (Delegate) = {obj_ref(ctx, o)}.{ctx.nm(fn)}")
    elif typ in ("MulticastDelegateProperty", "MulticastInlineDelegateProperty", "MulticastSparseDelegateProperty"):
        cnt = r.i32()
        parts = []
        for _ in range(min(cnt, 16)):
            o = r.i32()
            fn, fnn = r.fname()
            parts.append(f"{obj_ref(ctx, o)}.{ctx.nm(fn)}")
        lines.append(f"{ind}{name} ({typ}) = {parts}")
    else:
        blob = r.raw(size)
        lines.append(f"{ind}{name} ({typ} {size}B) {blob[:40].hex(' ')}")


def parse_summary(a):
    names, _ = read_names(a)
    ecnt, eoff = struct.unpack("<ii", a[0x39:0x41])
    icnt, ioff = struct.unpack("<ii", a[0x41:0x49])
    hdr = struct.unpack("<i", a[0x18:0x1C])[0]
    imports = []
    for k in range(icnt):
        o = ioff + k * 28
        imports.append(struct.unpack("<7i", a[o:o + 28]))
    exports = []
    if ecnt:
        stride = None
        for S in range(48, 264, 8):
            ok, prev = True, None
            for k in range(ecnt):
                o = eoff + k * S
                if o + 40 > len(a):
                    ok = False
                    break
                nidx, nnum, flags, ssize, rel, absf = struct.unpack("<6i", a[o + 16:o + 40])
                if not (0 <= nidx < len(names)) or ssize < 0 or absf < hdr or absf + ssize > hdr + 0x10000000:
                    ok = False
                    break
                if prev is not None and absf != prev:
                    ok = False
                    break
                prev = absf + ssize
            if ok:
                stride = S
                break
        if stride is None:
            return names, imports, exports, hdr, None
        for k in range(ecnt):
            o = eoff + k * stride
            cls, sup, tpl, outer, nidx, nnum, flags, ssize, rel, absf = struct.unpack("<10i", a[o:o + 40])
            exports.append({"cls": cls, "outer": outer, "nidx": nidx, "flags": flags,
                            "size": ssize, "abs": absf, "stride": stride})
    return names, imports, exports, hdr, stride


def dump_asset(ap, ep):
    a = ap.read_bytes()
    e = ep.read_bytes() if ep.exists() else b""
    try:
        names, imports, exports, hdr, stride = parse_summary(a)
    except Exception as ex:
        return None, f"summary fail: {ex}", []
    ctx = Ctx(names, imports, exports)
    out = io.StringIO()
    out.write(f"# {ap.relative_to(BASE).as_posix()}\n")
    out.write(f"# names={len(names)} imports={len(imports)} exports={len(exports)} "
              f"hdr={hdr} uexp={len(e)} stride={stride}\n")
    for j, im in enumerate(imports):
        out.write(f"import[{j}] class={ctx.nm(im[2])} ({ctx.nm(im[0])}) name={imp_path(ctx, j)}\n")
    miro = ([], None)  # material instance parameter rows
    for j, ex in enumerate(exports):
        cname = class_name(ctx, ex["cls"])
        out.write(f"\n=== export[{j}] '{ctx.nm(ex['nidx'])}' class={cname} "
                  f"outer={obj_ref(ctx, ex['outer'])} flags={ex['flags']:#x} "
                  f"size={ex['size']} @uexp+{ex['abs'] - hdr}\n")
        pos = ex["abs"] - hdr
        if pos < 0 or pos + ex["size"] > len(e):
            out.write(f"  <out of uexp range>\n")
            continue
        blob = e[pos:pos + ex["size"]]
        r = R(blob)
        n = 0
        resyncs = 0
        plines = []
        while r.off < len(blob) - 8 and resyncs < 24:
            try:
                n += parse_tagged_stream(r, ctx, plines, "  ")
                break
            except Fail:
                resyncs += 1
                base = r.off
                found = False
                for off in range(base + 1, min(len(blob), base + 8192)):
                    try:
                        rr = R(blob, off)
                        tag = read_tag(rr, ctx)
                        if tag is not None:
                            rr2 = R(blob, off)
                            probe = []
                            parse_tagged_stream(rr2, ctx, probe, "")
                            if probe:
                                plines.append(f"  <resync @{base:#x} -> {off:#x}, skipped {off - base}B "
                                              f"{blob[base:off][:24].hex(' ')}>")
                                r.off = off
                                found = True
                                break
                    except Fail:
                        continue
                if not found:
                    plines.append(f"  <unparseable tail @{base:#x}: {len(blob) - base}B "
                                  f"{blob[base:base + 32].hex(' ')}>")
                    break
        if plines:
            out.write("\n".join(plines) + "\n")
        if "MaterialInstance" in cname:
            miro = collect_mi_params(blob, ctx)
        out.write(f"  <{n} properties, {resyncs} resyncs>\n")
    return out.getvalue(), None, miro


def collect_mi_params(blob, ctx):
    """Extract scalar/vector/texture parameters from a MaterialInstance export blob."""
    rows = []
    r = R(blob)
    scalar = {}
    vector = {}
    texture = {}
    parent = [None]

    def grab(rr, nm_arr=""):
        pname = None
        while True:
            tag = read_tag(rr, ctx)
            if tag is None:
                return True
            nm, typ = tag["name"], tag["type"]
            if nm == "Parent" and typ == "ObjectProperty":
                parent[0] = obj_ref(ctx, rr.i32())
            elif nm == "ParameterInfo" and typ == "StructProperty":
                sub = R(rr.b, rr.off, min(rr.end, rr.off + tag["size"]))
                while True:
                    t3 = read_tag(sub, ctx)
                    if t3 is None:
                        break
                    if t3["name"] == "Name" and t3["type"] == "NameProperty":
                        v, _ = sub.fname()
                        pname = ctx.nm(v)
                    elif t3["type"] == "BoolProperty":
                        continue
                    else:
                        sub.raw(max(0, min(t3["size"], sub.end - sub.off)))
                rr.off = sub.off
            elif nm == "ParameterValue":
                if nm_arr == "scalar":
                    scalar[pname] = round(rr.f32(), 6)
                elif nm_arr == "vector":
                    vector[pname] = [round(x, 6) for x in struct.unpack("<4f", rr.raw(16))]
                elif nm_arr == "texture":
                    texture[pname] = obj_ref(ctx, rr.i32())
                else:
                    rr.raw(max(0, min(tag["size"], rr.end - rr.off)))
            elif nm == "ExpressionGUID":
                rr.raw(16)
            elif typ == "BoolProperty":
                continue
            elif typ in ("FloatProperty", "ObjectProperty", "NameProperty", "ByteProperty",
                         "UInt32Property", "StrProperty", "StructProperty", "GuidProperty",
                         "IntProperty", "Int64Property", "UInt64Property", "DoubleProperty",
                         "EnumProperty", "Int16Property", "UInt16Property", "Int8Property",
                         "InterfaceProperty", "AssetObjectProperty", "SoftObjectProperty",
                         "WeakObjectProperty", "LazyObjectProperty", "TextProperty"):
                rr.raw(tag["size"])
            elif typ == "ArrayProperty":
                cnt = rr.i32()
                inner = tag.get("inner")
                kind = ("scalar" if nm.startswith("Scalar") else
                        "vector" if nm.startswith("Vector") else
                        "texture" if nm.startswith("Texture") else "")
                if inner == "StructProperty" and cnt > 0:
                    tslot = struct.unpack("<I", rr.b[rr.off + 8:rr.off + 12])[0]
                    if tslot < len(ctx.names) and ctx.nm(tslot) == "StructProperty":
                        rr.raw(49)
                        for _ in range(min(cnt, 256)):
                            if not grab(rr, kind):
                                return False
                        continue
                rr.raw(max(0, min(tag["size"] - 4, rr.end - rr.off)))
            else:
                return False
    try:
        grab(r)
    except Fail:
        pass
    for k, v in scalar.items():
        rows.append(("scalar", k, json.dumps(v)))
    for k, v in vector.items():
        rows.append(("vector", k, json.dumps(v)))
    for k, v in texture.items():
        rows.append(("texture", k, v))
    return rows, parent[0]


def main():
    t0 = time.time()
    OUT_PROPS.mkdir(parents=True, exist_ok=True)
    OUT_MATS.mkdir(parents=True, exist_ok=True)
    cats = sorted(d for d in BASE.iterdir() if d.is_dir() and d.name.startswith("res_"))
    census = []
    mi_rows = []
    n_done = n_fail = 0
    for cat in cats:
        assets = sorted(cat.rglob("*.uasset"))
        for ap in assets:
            rel = ap.relative_to(BASE)
            if not RE_SAFE.match(rel.as_posix()):
                continue
            ep = ap.with_suffix(".uexp")
            if not ep.exists():
                continue
            try:
                txt, err, miro = dump_asset(ap, ep)
            except Exception as ex:
                txt, err, miro = None, f"dump fail: {ex!r}", []
            dest = OUT_PROPS / cat.name / ap.relative_to(cat).with_suffix(".txt")
            if not dest.resolve().parent.is_relative_to(OUT_PROPS.resolve()):
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            if txt is not None:
                dest.write_text(txt, encoding="utf-8", errors="replace")
                n_done += 1
                status = "ok"
            else:
                dest.write_text(f"# parse failure: {err}\n", encoding="utf-8")
                n_fail += 1
                status = "fail"
            census.append([rel.as_posix(), status, err or ""])
            if miro:
                rows, parent = miro
                for typ, k, v in rows:
                    mi_rows.append([rel.as_posix(), parent or "", typ, k, v])
        print(f"{cat.name}: {len(assets)} assets ({time.time() - t0:.0f}s)", flush=True)

    with (OUT_MATS / "instances.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["asset", "parent", "kind", "param", "value"])
        w.writerows(mi_rows)
    with (OUT / "properties_census.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["asset", "status", "error"])
        w.writerows(census)
    print(f"DONE assets_ok={n_done} fail={n_fail} mi_rows={len(mi_rows)} {time.time() - t0:.0f}s", flush=True)


if __name__ == "__main__":
    main()
