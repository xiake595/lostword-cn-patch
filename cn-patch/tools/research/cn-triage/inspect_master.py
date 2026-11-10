import zipfile, zlib, json
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
# master sample
names = [n for n in z.namelist() if n.startswith('lwlocal/master/') and n.endswith(('2a6550dc00714c9159b6e31fa9f8bb39','1251c9e74e6c3ce965363d7b858e7cd4','077aacf7784f4f7354e7f716e3ec0bcf'))]
for n in names:
    d = z.read(n)
    print('===', n, len(d), d[:16])
    for enc in ('utf-8',):
        i = d.find('{'.encode())
        print('  first { at', i)
    # try zlib decompress at various offsets
    for off in range(0, min(len(d), 64)):
        try:
            o = zlib.decompress(d[off:])
            print('  zlib ok at', off, 'len', len(o), o[:80])
            break
        except Exception:
            pass
    # printable scan
    import re
    txt = re.findall(rb'[\x20-\x7e]{6,}', d[:4000])
    print('  ascii head:', txt[:6])
