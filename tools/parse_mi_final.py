#!/usr/bin/env python3
"""Dragon Raja UE4 unversioned MI parser — FINAL (fully cracked, iguf 12.15).

Tag:      [FName name 8B][FName type 8B][i32 size][i32 arridx]
          [inner FName 8B for Struct/Array | u8 boolval for Bool]
          [u8 hasguid][FGuid 16B if hasguid][payload]
Array:    payload = [i32 count][block header 49B:
            name=<array name>, type=StructProperty, size=count*stride,
            arridx=0, inner=<element struct>, hasguid=0, guid=16B zeros]
          [count elements]; element = tagged member stream ending with None
          (name=(42,0) + type=(0,0)).
"""
import struct

from parse_mi_uasset import read_names

ASSET = r"D:\项目\dragonraja\unpacked\spinemats\M_UI_TEST_Inst.uasset"
UEXP = r"D:\项目\dragonraja\unpacked\spinemats\m_ui_test_inst.uexp"


class R:
    def __init__(self, b, off=0):
        self.b, self.off = b, off
    def u8(self):
        v = self.b[self.off]; self.off += 1; return v
    def i32(self):
        v = struct.unpack("<i", self.b[self.off:self.off + 4])[0]; self.off += 4; return v
    def fname(self):
        i, n = struct.unpack("<Ii", self.b[self.off:self.off + 8]); self.off += 8; return (i, n)
    def raw(self, n):
        v = self.b[self.off:self.off + n]; self.off += n; return v


def nm(names, i):
    return names[i] if 0 <= i < len(names) else f"?{i}"


def read_tag(r, names):
    """Read one FPropertyTag; returns (name, type, inner, payload, arridx, boolval) or None at terminator."""
    NONE = names.index("None")
    if r.off + 26 > len(r.b):
        return None
    ni, _ = r.fname()
    if ni == NONE:
        return None
    ti, _ = r.fname()
    typ = nm(names, ti)
    name = nm(names, ni)
    size = r.i32()
    arridx = r.i32()
    inner = None
    boolval = None
    if typ in ("StructProperty", "ArrayProperty"):
        ii, _ = r.fname(); inner = nm(names, ii)
    elif typ == "ByteProperty":
        r.fname()          # enum name (type-specific slot)
    elif typ == "BoolProperty":
        boolval = r.u8()
    if r.u8(): r.raw(16)
    if typ == "StructProperty":
        r.raw(16)          # Struct tags: 16B guid block ALWAYS present (zeros if none)
    payload = r.raw(size) if size > 0 else b""
    return (name, typ, inner, payload, arridx, boolval)


def parse_members(r, names, depth):
    """Parse a tagged member stream until None."""
    pad = "  " * depth
    while r.off + 26 <= len(r.b):
        tag = read_tag(r, names)
        if tag is None:
            break
        name, typ, inner, payload, arridx, boolval = tag
        if typ == "StructProperty" and inner == "LinearColor":
            print(f"{pad}{name} [LinearColor] = {tuple(round(x,6) for x in struct.unpack('<4f', payload[:16]))}")
        elif typ == "StructProperty" and inner == "Guid":
            print(f"{pad}{name} [Guid] = {payload[:16].hex()}")
        elif typ == "StructProperty" and inner == "MaterialParameterInfo":
            parse_members(R(payload), names, depth + 1)
        elif typ == "NameProperty":
            i, n = struct.unpack("<Ii", payload[:8])
            print(f"{pad}{name} [Name] = {nm(names, i)}")
        elif typ == "FloatProperty":
            print(f"{pad}{name} [Float] = {struct.unpack('<f', payload[:4])[0]:.6g}")
        elif typ == "BoolProperty":
            print(f"{pad}{name} [Bool] = {bool(boolval)}")
        elif typ == "ObjectProperty":
            print(f"{pad}{name} [Object] = {struct.unpack('<i', payload[:4])[0]}")
        elif typ == "ByteProperty":
            i, _ = struct.unpack("<Ii", payload[:8])
            print(f"{pad}{name} [Byte enum] = {nm(names, i)}")
        elif typ == "IntProperty":
            print(f"{pad}{name} [Int] = {struct.unpack('<i', payload[:4])[0]}")
        else:
            print(f"{pad}{name} [{typ}:{inner}] size={len(payload)}")


def main():
    a = open(ASSET, "rb").read()
    e = open(UEXP, "rb").read()
    names, _ = read_names(a)
    r = R(e)
    try:
        while r.off + 26 <= len(r.b):
            tag = read_tag(r, names)
            if tag is None:
                break
            name, typ, inner, payload, arridx, boolval = tag
            if typ == "ArrayProperty":
                sub = R(payload)
                cnt = sub.i32()
                hdr = sub.raw(33)      # envelope tag head: name8 type8 size4 arridx4 inner8 hasguid1
                hname, _ = struct.unpack("<Ii", hdr[0:8])
                hinner, _ = struct.unpack("<Ii", hdr[24:32])
                sub.raw(16)            # envelope guid block (zeros)
                print(f"{name} [Array:{inner}] count={cnt} envelope: name={nm(names,hname)} "
                      f"inner={nm(names,hinner)}")
                for k in range(cnt):
                    print(f"-- elem {k}")
                    parse_members(sub, names, 1)
            elif typ == "StructProperty":
                print(f"{name} [Struct:{inner}] size={len(payload)}")
                if inner == "MaterialInstanceBasePropertyOverrides":
                    parse_members(R(payload), names, 1)
            elif typ == "BoolProperty":
                print(f"{name} [Bool] = {bool(boolval)}")
            elif typ == "ObjectProperty":
                print(f"{name} [Object] = {struct.unpack('<i', payload[:4])[0]}")
            else:
                print(f"{name} [{typ}] size={len(payload)}")
    except struct.error:
        print(f"[end of property stream at {r.off:#x} — shader map data follows]")


if __name__ == "__main__":
    main()
