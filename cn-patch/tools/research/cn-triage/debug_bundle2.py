import sys, struct, zipfile
sys.path.insert(0, r'D:\Codex_Project\Lostword\work\cn-triage')
from unityfs import lz4_block_decompress, read_cstr

def hdr(data):
    off = 8
    ver = struct.unpack('>I', data[off:off+4])[0]; off += 4
    uv, off = read_cstr(data, off); ur, off = read_cstr(data, off)
    size = struct.unpack('>q', data[off:off+8])[0]; off += 8
    cbi, ubi = struct.unpack('>II', data[off:off+8]); off += 8
    flags = struct.unpack('>I', data[off:off+4])[0]; off += 4
    return ver, uv, ur, size, cbi, ubi, flags, off

def try_extract(data):
    ver, uv, ur, size, cbi, ubi, flags, off = hdr(data)
    print(f'  ver={ver} flags={flags:#x} cbi={cbi} ubi={ubi} off={off} file={len(data)}')
    comp = flags & 0x3f
    at_end = bool(flags & 0x80)
    pad_info = bool(flags & 0x200)
    if at_end:
        bi_off = len(data) - cbi
    else:
        bi_off = (off + 15) & ~15 if pad_info else off
    blob = data[bi_off:bi_off+cbi]
    for label, fn in (('lz4', lambda b: lz4_block_decompress(b, ubi)),
                      ('raw', lambda b: b)):
        try:
            raw = fn(blob)
            if len(raw) != ubi: continue
            print('   blocksinfo ok via', label)
            break
        except Exception as e:
            raw = None
    if raw is None:
        print('   blocksinfo FAIL'); return
    p = 16 if ver >= 7 else 0
    bc = struct.unpack('>i', raw[p:p+4])[0]; p += 4
    blocks = []
    for _ in range(bc):
        us, cs = struct.unpack('>II', raw[p:p+8]); p += 8
        fl = struct.unpack('>H', raw[p:p+2])[0]; p += 2
        blocks.append((us, cs, fl))
    nc = struct.unpack('>i', raw[p:p+4])[0]; p += 4
    print('   blocks', bc, 'nodes', nc, 'sum_cs', sum(b[1] for b in blocks))
    data_off = (bi_off + cbi + 15) & ~15 if not at_end else off
    # try candidate data offsets: exact, align16, align16 of (off)
    cands = []
    for base in (off, (off+15)&~15):
        for block_pad in (0, 1):
            cands.append((base, block_pad))
    for base, bpad in cands:
        try:
            out = bytearray(); pos = base; ok = True
            for (us, cs, fl) in blocks:
                if bpad: pos = (pos + 15) & ~15
                chunk = data[pos:pos+cs]; pos += cs
                if cs != us:
                    chunk = lz4_block_decompress(chunk, us)
                out += chunk
            print(f'   cand base={base} bpad={bpad} -> out={len(out)} head={out[:8].hex()}')
            if len(out) > 100 and out[0] in (0x00,) and out[1] in (0x00,):
                print('      head u32', struct.unpack('>I', out[:4])[0])
        except Exception as e:
            print(f'   cand base={base} bpad={bpad} FAIL {e!r}')

z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
for name in ['lwlocal/bundles/058ca74ee3b190798624c697eda9144d/db0b1194b37961915dbd1b969e3a2065/__data',
             'lwlocal/bundles/03c422e7816384e6b20693a752a1a89d/d52eb2472f01af61a5446eed14f6666e/__data']:
    print('===', name.split('/')[-3], len(z.read(name)))
    try_extract(z.read(name))
