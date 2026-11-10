import zipfile, zlib, lzma, sys, math, collections
sys.path.insert(0, r'D:\Codex_Project\Lostword\work\cn-triage')
from unityfs import lz4_block_decompress
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
n = 'lwlocal/master/077aacf7784f4f7354e7f716e3ec0bcf'
d = z.read(n)
print('size', len(d), 'head', d[:16].hex())

def printable_ratio(b):
    if not b: return 0
    return sum(1 for x in b if 32 <= x < 127 or x in (9,10,13)) / len(b)

# zlib raw deflate
for wbits in (15, -15, 31, 47):
    try:
        out = zlib.decompress(d, wbits)
        print('zlib wbits', wbits, '->', len(out), 'printable', round(printable_ratio(out),3), out[:80])
    except Exception as e:
        pass

# lzma alone/raw/auto
for fmt in (lzma.FORMAT_AUTO, lzma.FORMAT_ALONE, lzma.FORMAT_XZ):
    try:
        out = lzma.decompress(d, format=fmt)
        print('lzma fmt', fmt, '->', len(out), 'printable', round(printable_ratio(out),3), out[:80])
    except Exception as e:
        pass
# lzma raw with common props (lc=3,lp=0,pb=2, dict 64MB)
for dict_size in (1<<16, 1<<20, 1<<24, 1<<26):
    try:
        filt = [{'id': lzma.FILTER_LZMA1, 'dict_size': dict_size, 'lc': 3, 'lp': 0, 'pb': 2}]
        out = lzma.decompress(d, format=lzma.FORMAT_RAW, filters=filt)
        print('lzma raw dict', dict_size, '->', len(out), 'printable', round(printable_ratio(out),3), out[:80])
    except Exception as e:
        pass
# lz4 block (dest size 0 -> no check)
try:
    out = lz4_block_decompress(d, 0)
    print('lz4 ->', len(out), 'printable', round(printable_ratio(out),3), out[:80])
except Exception as e:
    print('lz4 fail', repr(e))
# brotli
try:
    import brotli
    out = brotli.decompress(d)
    print('brotli ->', len(out), out[:80])
except Exception as e:
    print('brotli n/a', repr(e))
