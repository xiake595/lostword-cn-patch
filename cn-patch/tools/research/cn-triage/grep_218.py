import re
p = r'D:\Codex_Project\Lostword\work\dev-cache\extract_hits2\218d248860d4e311e25b70b6497334d4_5833fefffd29a78acc4f52e91fcb2ece___data.raw'
d = open(p, 'rb').read()
print('size', len(d))
for pat in [b'Complete', b'Errand', b'Daily', b'Limited', b'Remaining', b'Time']:
    print('==', pat)
    start = 0; n = 0
    while True:
        i = d.find(pat, start)
        if i < 0: break
        n += 1
        if n <= 6:
            print('   @', i, repr(d[max(0,i-50):i+80]))
        start = i + 1
    print('   total', n)
