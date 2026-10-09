#!/usr/bin/env python3
"""Minimal UE4 cooked-package reader for MaterialInstanceConstant exports.

Parses the uasset name table, then walks the uexp tagged-property stream of the
first export, printing ScalarParameterValues / VectorParameterValues /
TextureParameterValues with resolved names and values.

Usage: parse_mi_uasset.py <uasset_path> <uexp_path>
"""
import struct
import sys


def read_names(a):
    # summary: magic(4) ver(4x3) licensee(4) custom-count(4) total-header(4) folder-FString
    # then PackageFlags(4) NameCount(4) NameOffset(4)
    o = 24  # after custom-versions count (assumed 0)
    total, = struct.unpack("<i", a[o:o + 4])
    o += 4
    _, o = fstr_bytes(a, o)  # folder name
    o += 4  # package flags
    name_count, name_off = struct.unpack("<ii", a[o:o + 8])
    names = []
    pos = name_off
    for _ in range(name_count):
        ln = struct.unpack("<i", a[pos:pos + 4])[0]
        if ln < 0:
            # UTF-16 FString (non-ASCII name, e.g. Chinese parameter names)
            n = -ln
            names.append(a[pos + 4:pos + 4 + 2 * (n - 1)].decode("utf-16-le", "replace"))
            pos += 4 + 2 * n + 4  # FString + u32 hash
        else:
            names.append(a[pos + 4:pos + 4 + ln - 1].decode("utf-8", "replace"))
            pos += 4 + ln + 4  # FString + u32 hash
    return names, pos


def fstr_bytes(b, off):
    ln = struct.unpack("<i", b[off:off + 4])[0]
    return b[off + 4:off + 4 + ln - 1].decode("utf-8", "replace"), off + 4 + ln


def fstr(b, off):
    ln = struct.unpack("<i", b[off:off + 4])[0]
    if ln == 0:
        return "", off + 4
    if ln > 0:
        return b[off + 4:off + 4 + ln - 1].decode("utf-8", "replace"), off + 4 + ln
    # UTF-16
    n = -ln
    return b[off + 4:off + 4 + 2 * (n - 1)].decode("utf-16-le", "replace"), off + 4 + 2 * n


ASSET = r"D:\项目\dragonraja\unpacked\spinemats\M_UI_TEST_Inst.uasset"
UEXP = r"D:\项目\dragonraja\unpacked\spinemats\m_ui_test_inst.uexp"


def main():
    a = open(ASSET, "rb").read()
    e = open(UEXP, "rb").read()
    names, _ = read_names(a)
    nidx = {n: i for i, n in enumerate(names)}
    print(f"names: {len(names)} ({names[0]}..{names[-1]})")

    pos = 0
    NONE = nidx.get("None")

    def pname(i):
        return names[i] if 0 <= i < len(names) else f"?{i}"

    while pos + 8 <= len(e):
        ni, ti = struct.unpack("<II", e[pos:pos + 8])
        if ni == NONE and ti == NONE:
            print("[None] end of properties @", hex(pos))
            break
        name, typ = pname(ni), pname(ti)
        pos += 8
        if typ in ("FloatProperty", "IntProperty", "ByteProperty", "BoolProperty", "UInt32Property"):
            size = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += 4
            val = struct.unpack("<f" if typ == "FloatProperty" else "<i", e[pos:pos + 4])[0]
            pos += size
            print(f"{name} ({typ}) = {val}")
        elif typ == "StructProperty":
            sname = pname(struct.unpack("<I", e[pos:pos + 4])[0])
            pos += 4 + 16  # struct name + guid
            size = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += 4
            payload = e[pos:pos + size]
            pos += size
            if sname == "LinearColor":
                v = struct.unpack("<4f", payload[:16])
                print(f"{name} (LinearColor) = {tuple(round(x,5) for x in v)}")
            elif sname == "MaterialParameterInfo":
                s, o2 = fstr(payload, 0)
                print(f"{name} (ParamInfo) = {s!r}")
            elif sname == "ColorMaterialInput" or sname.endswith("Input"):
                print(f"{name} (input {sname}, {size}B)")
            else:
                print(f"{name} (struct {sname}, {size}B)")
        elif typ == "ArrayProperty":
            inner = pname(struct.unpack("<I", e[pos:pos + 4])[0])
            pos += 4
            size = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += 4
            cnt = struct.unpack("<i", e[pos:pos + 4])[0]
            print(f"{name} (Array of {inner}, {size}B, count={cnt}) @", hex(pos))
            if inner == "StructProperty" and cnt > 0 and cnt < 200:
                o = pos + 4
                for k in range(cnt):
                    sname = pname(struct.unpack("<I", e[o:o + 4])[0])
                    o += 4 + 16
                    esz = struct.unpack("<i", e[o:o + 4])[0]
                    o += 4
                    pl = e[o:o + esz]
                    o += esz
                    if sname == "ScalarParameterValue":
                        s, o2 = fstr(pl, 0)
                        guid = pl[o2:o2 + 16]
                        val = struct.unpack("<f", pl[o2 + 16:o2 + 20])[0]
                        print(f"   scalar {s!r} = {val}")
                    elif sname == "VectorParameterValue":
                        s, o2 = fstr(pl, 0)
                        val = struct.unpack("<4f", pl[o2 + 16:o2 + 32])
                        print(f"   vector {s!r} = {tuple(round(x,5) for x in val)}")
                    elif sname == "TextureParameterValue":
                        s, o2 = fstr(pl, 0)
                        obj = struct.unpack("<i", pl[o2 + 16:o2 + 20])[0]
                        print(f"   texture {s!r} -> obj {obj}")
                    else:
                        print(f"   [{sname} {esz}B]")
            else:
                pos += size
        elif typ == "ObjectProperty":
            size = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += 4
            val = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += size
            print(f"{name} (Object) = {val}")
        elif typ == "BoolProperty":
            val = e[pos]
            pos += 1
            print(f"{name} (Bool) = {bool(val)}")
        elif typ == "NameProperty":
            size = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += 4
            val = pname(struct.unpack("<I", e[pos:pos + 4])[0])
            pos += size
            print(f"{name} (Name) = {val}")
        elif typ == "StrProperty":
            size = struct.unpack("<i", e[pos:pos + 4])[0]
            pos += 4
            s, o2 = fstr(e, pos)
            pos += size
            print(f"{name} (Str) = {s!r}")
        else:
            print(f"?{typ} for {name} @ {hex(pos-8)} — stop")
            break


if __name__ == "__main__":
    main()
