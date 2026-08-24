"""Read a PE's VS_VERSIONINFO the way the format actually defines it.

Every node is {wLength, wValueLength, wType, szKey (utf-16, NUL), pad, Value, Children},
each member aligned to 4 bytes. Walking it properly matters: a heuristic scan for
"InternalName" picks up the key but guesses at where the value stops, and these strings
are short enough that being one character off changes the answer.
"""
import struct, sys, os

def _align4(n): return (n + 3) & ~3

def _wstr(d, at):
    e = at
    while e + 1 < len(d) and d[e:e+2] != b'\x00\x00':
        e += 2
    return d[at:e].decode('utf-16-le', 'replace'), e + 2

def _node(d, at, end):
    if at + 6 > end: return None
    ln, vlen, typ = struct.unpack_from('<HHH', d, at)
    if ln == 0 or at + ln > end: return None
    key, after = _wstr(d, at + 6)
    return {'at': at, 'len': ln, 'vlen': vlen, 'type': typ, 'key': key,
            'val_at': _align4(after), 'end': at + ln}

def _children(d, node, from_at):
    out, at = [], _align4(from_at)
    while at < node['end']:
        c = _node(d, at, node['end'])
        if not c: break
        out.append(c)
        at = _align4(c['end'])
    return out

def read(path):
    d = open(path, 'rb').read()
    i = d.find('VS_VERSION_INFO'.encode('utf-16-le'))
    if i < 0: return None
    root = _node(d, i - 6, len(d))
    if not root or root['key'] != 'VS_VERSION_INFO': return None
    # skip the fixed VS_FIXEDFILEINFO if present
    after_fixed = _align4(root['val_at'] + root['vlen'])
    fields = {}
    for blk in _children(d, root, after_fixed):
        if blk['key'] != 'StringFileInfo': continue
        for tbl in _children(d, blk, blk['val_at']):
            for s in _children(d, tbl, tbl['val_at']):
                v, _ = _wstr(d, s['val_at'])
                if v: fields[s['key']] = v.rstrip('\x00').strip()
    return fields

if __name__ == '__main__':
    KEYS = ['CompanyName','ProductName','FileDescription','InternalName','OriginalFilename',
            'FileVersion','ProductVersion','LegalCopyright','Comments','SpecialBuild','PrivateBuild']
    print('\t'.join(['file'] + KEYS))
    for p in sys.argv[1:]:
        try: f = read(p)
        except Exception: continue
        if not f: continue
        print('\t'.join([p] + [f.get(k, '') for k in KEYS]))
