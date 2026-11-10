import sys, struct, zipfile
sys.path.insert(0, r'D:\Codex_Project\Lostword\work\cn-triage')
from unityfs import lz4_block_decompress, read_cstr

def align16(x): return (x + 15) & ~15

def extract(data):
    off = 8
    ver = struct.unpack('>I', data[off:off+4])[0]; off += 4
    uv, off = read_cstr(data, off); ur, off = read_cstr(data, off)
    size = struct.unpack('>q', data[off:off+8])[0]; off += 8
    cbi, ubi = struct.unpack('>II', data[off:off+8]); off += 8
    flags = struct.unpack('>I', data[off:off+4])[0]; off += 4
    comp = flags & 0x3f
    at_end = bool(flags & 0x80)
    pad_info = bool(flags & 0x200)
    if at_end:
        bi_off = len(data) - cbi
    else:
        bi_off = align16(off) if pad_info else off
    blob = data[bi_off:bi_off+cbi]
    if comp in (2, 3):
        raw = lz4_block_decompress(blob, ubi)
    elif comp == 0:
        raw = blob
    else:
        raise ValueError('comp %d' % comp)
    p = 16 if ver >= 7 else 0
    bc = struct.unpack('>i', raw[p:p+4])[0]; p += 4
    blocks = []
    for _ in range(bc):
        us, cs = struct.unpack('>II', raw[p:p+8]); p += 8
        fl = struct.unpack('>H', raw[p:p+2])[0]; p += 2
        blocks.append((us, cs, fl))
    if at_end:
        data_off = align16(off)
    else:
        info_end = bi_off + cbi
        data_off = align16(info_end) if pad_info else info_end
    out = bytearray(); pos = data_off
    for (us, cs, fl) in blocks:
        chunk = data[pos:pos+(us if cs == 0 else cs)]
        take = us if cs == 0 else cs
        chunk = data[pos:pos+take]; pos += take
        if cs != 0 and cs != us:
            chunk = lz4_block_decompress(chunk, us)
        out += chunk
    return {'ver': ver, 'flags': flags, 'blocks': blocks, 'data': bytes(out),
            'data_off': data_off, 'size': size, 'uv': uv}

z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
for name in ['lwlocal/bundles/058ca74ee3b190798624c697eda9144d/db0b1194b37961915dbd1b969e3a2065/__data',
             'lwlocal/bundles/03c422e7816384e6b20693a752a1a89d/d52eb2472f01af61a5446eed14f6666e/__data']:
    d = z.read(name)
    print('===', name.split('/')[-3], len(d))
    try:
        r = extract(d)
        out = r['data']
        print('  ver', r['ver'], 'flags', hex(r['flags']), 'blocks', len(r['blocks']), 'out', len(out), 'data_off', r['data_off'])
        print('  head', out[:64].hex())
        # find unity version cstr: after 4-byte version, u32 len + chars
        i = out.find(b'6000')
        print('  6000 at', i, out[max(0,i-8):i+16])
        print('  Errand count', out.count(b'Errand'), 'APP_ERRAND', out.count(b'APP_ERRAND'))
    except Exception as e:
        print('  FAIL', repr(e))
