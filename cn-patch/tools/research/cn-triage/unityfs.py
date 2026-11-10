import struct, os, zlib, lzma, json

def lz4_block_decompress(src, dest_size):
    dst = bytearray(); i = 0; n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        dst += src[i:i+lit]; i += lit
        if i >= n: break
        offset = src[i] | (src[i+1] << 8); i += 2
        mlen = token & 0x0F
        if mlen == 15:
            while True:
                b = src[i]; i += 1; mlen += b
                if b != 255: break
        mlen += 4
        start = len(dst) - offset
        if start < 0: raise ValueError('bad lz4 offset')
        for k in range(mlen): dst.append(dst[start+k])
    if dest_size and len(dst) != dest_size:
        raise ValueError('lz4 size mismatch %d != %d' % (len(dst), dest_size))
    return bytes(dst)

def read_cstr(data, off):
    end = data.index(b'\x00', off)
    return data[off:end].decode('latin-1'), end+1

def extract_unityfs(data):
    assert data[:8] == b'UnityFS\x00', data[:8]
    off = 8
    version = struct.unpack('>I', data[off:off+4])[0]; off += 4
    unity_ver, off = read_cstr(data, off)
    unity_rev, off = read_cstr(data, off)
    size = struct.unpack('>q', data[off:off+8])[0]; off += 8
    cbi, ubi = struct.unpack('>II', data[off:off+8]); off += 8
    flags = struct.unpack('>I', data[off:off+4])[0]; off += 4
    compression = flags & 0x3F
    blocks_info_at_end = bool(flags & 0x80)
    # locate blocks info
    if blocks_info_at_end:
        bi_off = len(data) - cbi
        data_off = off
    else:
        bi_off = off
        data_off = off + cbi
    blob = data[bi_off:bi_off+cbi]
    if compression in (2, 3):
        raw = lz4_block_decompress(blob, ubi)
    elif compression == 0:
        raw = blob
    elif compression == 1:
        raw = lzma.decompress(blob)
    else:
        raise ValueError('unknown compression %d' % compression)
    # parse blocks
    p = 0
    # v7+: 16-byte hash
    if version >= 7:
        p += 16
    block_count = struct.unpack('>i', raw[p:p+4])[0]; p += 4
    blocks = []
    for _ in range(block_count):
        us, cs = struct.unpack('>II', raw[p:p+8]); p += 8
        fl = struct.unpack('>H', raw[p:p+2])[0]; p += 2
        blocks.append((us, cs, fl))
    node_count = struct.unpack('>i', raw[p:p+4])[0]; p += 4
    nodes = []
    for _ in range(node_count):
        noff, nsize = struct.unpack('>qq', raw[p:p+16]); p += 16
        fl = struct.unpack('>I', raw[p:p+4])[0]; p += 4
        path, p = read_cstr(raw, p)
        nodes.append((noff, nsize, fl, path))
    # read block data
    out = bytearray(); pos = data_off
    for (us, cs, fl) in blocks:
        # flags in block: 0x01 = compressed? Unity uses block flags 0x01 stored, 0x02 lz4, 0x04 lzma?
        if cs == 0 or cs == us:
            chunk = data[pos:pos+us]
            pos += us
        else:
            chunk = data[pos:pos+cs]
            pos += cs
            try:
                chunk = lz4_block_decompress(chunk, us)
            except Exception:
                if compression == 1:
                    chunk = lzma.decompress(chunk)
                else:
                    raise
        out += chunk
    return {'version': version, 'unity': unity_ver, 'rev': unity_rev, 'flags': flags,
            'compression': compression, 'blocks': blocks, 'nodes': nodes, 'data': bytes(out)}

if __name__ == '__main__':
    import sys, zipfile
    if len(sys.argv) >= 3 and sys.argv[1] == 'zip':
        z = zipfile.ZipFile(sys.argv[2])
        names = [n for n in z.namelist() if n.startswith('lwlocal/bundles/')]
        target = sys.argv[3] if len(sys.argv) > 3 else None
        for n in names:
            if target and target not in n: continue
            try:
                r = extract_unityfs(z.read(n))
                print(n, 'ok blocks', len(r['blocks']), 'data', len(r['data']), 'nodes', len(r['nodes']))
                for nd in r['nodes'][:5]: print('   node', nd)
            except Exception as e:
                print(n, 'FAIL', repr(e))
    else:
        r = extract_unityfs(open(sys.argv[1], 'rb').read())
        print(json.dumps({k: v for k, v in r.items() if k != 'data'}, indent=1)[:1500])
        open(sys.argv[1] + '.raw', 'wb').write(r['data'])
        print('raw written', len(r['data']))
