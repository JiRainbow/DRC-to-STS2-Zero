#!/usr/bin/env python3
"""Dump wLua registration table around given vaddr using .rela.dyn RELATIVE addends."""
import sys, struct
from elftools.elf.elffile import ELFFile

SO = r"D:\项目\dragonraja\unpacked\so\libUE4.so"

def main():
    center = int(sys.argv[1], 16)
    span = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x100
    lo, hi = center - span, center + span

    f = open(SO, "rb")
    elf = ELFFile(f)
    segs, secs = [], []
    for seg in elf.iter_segments():
        if seg["p_type"] == "PT_LOAD":
            segs.append((seg["p_vaddr"], seg["p_memsz"], seg["p_offset"], seg["p_filesz"]))
    for s in elf.iter_sections():
        if s["sh_addr"]:
            secs.append((s["sh_addr"], s["sh_size"], s.name))

    def v2o(v):
        for va, msz, off, fsz in segs:
            if va <= v < va + msz:
                return off + (v - va) if (v - va) < fsz else None
        return None

    def classify(v):
        for va, sz, name in secs:
            if va <= v < va + sz:
                return name
        return None

    def cstr(v, maxlen=96):
        o = v2o(v)
        if o is None: return None
        f.seek(o); b = f.read(maxlen)
        z = b.find(b"\0")
        if z >= 0: b = b[:z]
        try: s = b.decode("utf-8")
        except: return None
        if s and all(c == "\t" or 32 <= ord(c) < 0xFFFD for c in s): return s
        return None

    # rela.dyn RELATIVE map
    rela = elf.get_section_by_name(".rela.dyn")
    slots = {}
    for r in rela.iter_relocations():
        if r["r_info_type"] == 1027:  # R_AARCH64_RELATIVE
            off = r["r_offset"]
            if lo <= off < hi:
                slots[off] = r["r_addend"]

    print(f"RELATIVE slots in [0x{lo:x},0x{hi:x}): {len(slots)}")
    for off in sorted(slots):
        q = slots[off]
        cls = classify(q)
        tag = f"-> {cls}" if cls else ""
        if cls and "text" in cls:
            tag = f"-> FUN_{q:08x}"
        elif cls and ("rodata" in cls or "data.rel" in cls):
            s = cstr(q)
            if s: tag = f'-> {cls} "{s}"'
        mark = " <<<" if off == center else ""
        print(f"  0x{off:x}: 0x{q:012x} {tag}{mark}")

if __name__ == "__main__":
    main()
