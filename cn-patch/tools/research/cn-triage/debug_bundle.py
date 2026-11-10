import sys, struct, zipfile
sys.path.insert(0, r'D:\Codex_Project\Lostword\work\cn-triage')
from unityfs import lz4_block_decompress, read_cstr
sys.path.insert(0, r'D:\Codex_Project\Lostword\work\cn-analysis')
from parse_bundles import parse_header

z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
for name in ['lwlocal/bundles/058ca74ee3b190798624c697eda9144d/db0b1194b37961915dbd1b969e3a2065/__data',
             'lwlocal/bundles/03c422e7816384e6b20693a752a1a89d/d52eb2472f01af61a5446eed14f6666e/__data']:
    data = z.read(name)
    print('===', name, len(data))
    info = parse_header(data, verbose=False)
    print(' version', info.get('version'), 'flags', info.get('flags'), 'comp', info.get('compression'),
          'cbi', info.get('blocks_info_compressed_size'), 'ubi', info.get('blocks_info_uncompressed_size'),
          'loc', info.get('blocks_info_location'))
    blocks = info.get('blocks'); nodes = info.get('nodes')
    print(' blocks', blocks[:6], '... total', len(blocks or []))
    print(' nodes', [ (n['path'], n['size']) for n in (nodes or [])][:5])
    # header size
    off = 8
    ver = struct.unpack('>I', data[off:off+4])[0]; off += 4
    uv, off = read_cstr(data, off); ur, off = read_cstr(data, off)
    size = struct.unpack('>q', data[off:off+8])[0]; off += 8
    cbi, ubi = struct.unpack('>II', data[off:off+8]); off += 8
    flags = struct.unpack('>I', data[off:off+4])[0]; off += 4
    print(' header_end', off, 'file_size', len(data), 'declared', size, 'flags', hex(flags))
    # try block data at various offsets
    for data_off in (off, off+16, off- (len(data)-off) + 0):
        pass
    # assume blocks info at end; data begins at header end
    data_off = off
    print(' first bytes at data_off:', data[data_off:data_off+32].hex())
    print(' last 64 bytes:', data[-64:].hex())
