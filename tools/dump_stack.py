import struct

p = r'C:\Users\jirai\AppData\Local\CrashDumps\SlayTheSpire2.exe.29788.dmp'
data = open(p, 'rb').read()
nstreams, rva = struct.unpack_from('<II', data, 8)
pos = rva
streams = {}
for i in range(nstreams):
    st, sz, srva = struct.unpack_from('<III', data, pos)
    streams.setdefault(st, srva)
    pos += 12
srva = streams[6]
tid = struct.unpack_from('<I', data, srva)[0]
code = struct.unpack_from('<I', data, srva + 8)[0]
iaddr = struct.unpack_from('<Q', data, srva + 24)[0]
print(f'crash tid {tid} code {hex(code)} ip {hex(iaddr)}')
mrva = streams[4]
nmod = struct.unpack_from('<I', data, mrva)[0]
mrva += 4
mods = []
for i in range(nmod):
    e = mrva + i * 108
    mbase, msize = struct.unpack_from('<QQ', data, e)
    nrva = struct.unpack_from('<I', data, e + 20)[0]  # ModuleNameRva @20
    try:
        ln = struct.unpack_from('<I', data, nrva)[0]
        if ln == 0 or ln > 4000 or nrva + 4 + ln * 2 > len(data):
            continue
        name = data[nrva+4:nrva+4+ln*2].decode('utf-16-le', 'replace')
        if all(31 < ord(c) < 127 for c in name):
            mods.append((mbase, msize, name))
    except Exception:
        continue
print('valid modules:', len(mods))

def who(addr):
    for mbase, msize, name in mods:
        if mbase <= addr < mbase + msize:
            return f'{name.split(chr(92))[-1]}+{addr-mbase:#x}'
    return None

print('rip in:', who(iaddr) or hex(iaddr))
trva = streams[3]
nthr = struct.unpack_from('<I', data, trva)[0]
p = trva + 4
found = False
for i in range(nthr):
    tid2 = struct.unpack_from('<I', data, p)[0]
    if tid2 == tid:
        # MINIDUMP_THREAD: tid(4) suspend(4) priClass(4) pri(4) teb(8)
        # stack.start(8) stack.size(4) stack.rva(4) ctx.size(4) ctx.rva(4)
        ssize = struct.unpack_from('<I', data, p + 32)[0]
        srva2 = struct.unpack_from('<I', data, p + 36)[0]
        crva = struct.unpack_from('<I', data, p + 44)[0]
        found = True
        break
    p += 48
print('thread found:', found)
rip = struct.unpack_from('<Q', data, crva + 0xF8)[0]
rsp = struct.unpack_from('<Q', data, crva + 0x98)[0]
print(f'ctx rip={hex(rip)} rsp={hex(rsp)} rip_in={who(rip)}')
depth = 0
for off in range(0, min(ssize, 0x8000) - 8, 8):
    v = struct.unpack_from('<Q', data, srva2 + off)[0]
    w = who(v)
    if w and depth < 40:
        print(f'  {hex(rsp+off)}: {w}')
        depth += 1
