# -*- coding: utf-8 -*-
"""Parse UnityFS bundle headers (block info) to list internal asset paths.

Works for UnityFS v6/v7/v8 (version 8 incl. Unity 6000.0). Block info may be
LZ4-compressed; pure-python LZ4 block decoder used, no external deps.
"""
import struct
import sys
import json
import io


def lz4_block_decompress(src: bytes, dest_size: int) -> bytes:
    dst = bytearray()
    i = 0
    n = len(src)
    while i < n:
        token = src[i]
        i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        dst += src[i:i + lit]
        i += lit
        if i >= n:
            break
        if i + 2 > n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        mlen = token & 0x0F
        if mlen == 15:
            while True:
                b = src[i]
                i += 1
                mlen += b
                if b != 255:
                    break
        mlen += 4
        start = len(dst) - offset
        if start < 0:
            raise ValueError('bad lz4 offset')
        for k in range(mlen):
            dst.append(dst[start + k])
    if dest_size and len(dst) != dest_size:
        raise ValueError('lz4 size mismatch %d != %d' % (len(dst), dest_size))
    return bytes(dst)


def read_cstr(data: bytes, off: int):
    end = data.index(b'\x00', off)
    return data[off:end].decode('latin-1'), end + 1


def parse_blocks_info(raw: bytes):
    """Return (blocks, nodes). raw is uncompressed block-info blob."""
    off = 0
    # v7+: 16-byte hash of uncompressed data
    if len(raw) >= 16:
        off += 16
    block_count = struct.unpack('>i', raw[off:off + 4])[0]
    off += 4
    blocks = []
    for _ in range(block_count):
        usize, csize = struct.unpack('>II', raw[off:off + 8])
        off += 8
        flags = struct.unpack('>H', raw[off:off + 2])[0]
        off += 2
        blocks.append((usize, csize, flags))
    node_count = struct.unpack('>i', raw[off:off + 4])[0]
    off += 4
    nodes = []
    for _ in range(node_count):
        noff, nsize = struct.unpack('>qq', raw[off:off + 16])
        off += 16
        flags = struct.unpack('>I', raw[off:off + 4])[0]
        off += 4
        path, off = read_cstr(raw, off)
        nodes.append({'offset': noff, 'size': nsize, 'flags': flags, 'path': path})
    return blocks, nodes


def parse_header(data: bytes, verbose=True):
    if data[:7] != b'UnityFS':
        return {'magic': data[:8].decode('latin-1', 'replace')}
    off = 8
    version = struct.unpack('>I', data[off:off + 4])[0]
    off += 4
    unity_version, off = read_cstr(data, off)
    unity_revision, off = read_cstr(data, off)
    size = struct.unpack('>q', data[off:off + 8])[0]
    off += 8
    cbi_size, ubi_size = struct.unpack('>II', data[off:off + 8])
    off += 8
    flags = struct.unpack('>I', data[off:off + 4])[0]
    off += 4
    info = {
        'version': version,
        'unity_version': unity_version,
        'unity_revision': unity_revision,
        'declared_size': size,
        'blocks_info_compressed_size': cbi_size,
        'blocks_info_uncompressed_size': ubi_size,
        'flags': flags,
        'compression': flags & 0x3F,
        'blocks_info_at_end': bool(flags & 0x40),
    }
    # candidate locations of the compressed blocks-info blob
    candidates = []
    candidates.append(('after_header', data[off:off + cbi_size]))
    if len(data) >= cbi_size:
        candidates.append(('at_end', data[len(data) - cbi_size:]))
    raw = None
    used = None
    if (flags & 0x3F) == 0:
        for name, blob in candidates:
            if len(blob) == ubi_size:
                raw, used = blob, name
                break
    else:
        for name, blob in candidates:
            try:
                cand = lz4_block_decompress(blob, ubi_size)
            except Exception:
                continue
            raw, used = cand, name
            break
    info['blocks_info_location'] = used
    if raw is not None:
        try:
            blocks, nodes = parse_blocks_info(raw)
            info['blocks'] = blocks
            info['nodes'] = nodes
        except Exception as e:  # noqa
            info['blocks_parse_error'] = repr(e)
    if verbose:
        print(json.dumps(info, indent=1, ensure_ascii=False))
    return info


if __name__ == '__main__':
    path = sys.argv[1]
    with open(path, 'rb') as f:
        data = f.read()
    parse_header(data)
