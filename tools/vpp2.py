# Saints Row 2 packfiles (.vpp_pc, version 4, little-endian): list or extract.
#   python -I vpp2.py <file.vpp_pc> [out_dir] [glob]
import sys, struct, zlib, os, fnmatch
def up(x): return (x + 2047) & ~2047
def load(path):
    d = open(path, 'rb').read()
    u = lambda o: struct.unpack_from('<I', d, o)[0]
    assert u(0) == 0x51890ACE and u(4) == 4, "not an SR2 packfile"
    flags, n, dsz, nsz, esz = u(332), u(340), u(348), u(352), u(356)
    comp, cond = flags & 1, flags & 2
    names = up(0x800 + dsz); exts = up(names + nsz); data = up(exts + esz)
    def cstr(o): return d[o:d.index(b'\0', o)].decode('latin1')
    ents = []
    stored = data
    for i in range(n):
        e = 0x800 + i * 28
        name = cstr(names + u(e)) + '.' + cstr(exts + u(e + 4))
        at, size, csize = u(e + 12), u(e + 16), u(e + 20)
        if comp and not cond: at = stored; stored = up(stored + csize)
        ents.append((name, at, size, csize))
    blob = None
    if comp and cond: blob = zlib.decompress(d[data:])
    def read(e):
        name, at, size, csize = e
        if blob is not None: return blob[at:at + size]
        if comp: return zlib.decompress(d[at:at + csize])
        return d[data + at:data + at + size]
    return ents, read
if __name__ == '__main__':
    ents, read = load(sys.argv[1])
    pat = sys.argv[3] if len(sys.argv) > 3 else '*'
    ents = [e for e in ents if fnmatch.fnmatch(e[0].lower(), pat)]
    if len(sys.argv) > 2:
        os.makedirs(sys.argv[2], exist_ok=True)
        for e in ents: open(os.path.join(sys.argv[2], e[0]), 'wb').write(read(e))
        print("extracted", len(ents))
    else:
        for e in ents: print(e[2], e[0])
