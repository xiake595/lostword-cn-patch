import zipfile, math, collections, os
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
masters = [n for n in z.namelist() if n.startswith('lwlocal/master/')][:6]
for n in masters:
    d = z.read(n)
    c = collections.Counter(d)
    ent = -sum((v/len(d)) * math.log2(v/len(d)) for v in c.values())
    printable = sum(1 for b in d if 32 <= b < 127) / len(d)
    print(f'== {n.split("/")[-1]} size={len(d)} entropy={ent:.3f} printable={printable:.3f}')
    print('   head', d[:24].hex())
    print('   EAST?', d.find(b'EAST'), ' gzip', d[:2].hex(), ' zlib?', d[:2] in (b'\x78\x01', b'\x78\x9c', b'\x78\xda'))
    # single-byte xor test
    best = None
    for k in range(256):
        dec = bytes(b ^ k for b in d[:200])
        pr = sum(1 for b in dec if 32 <= b < 127 or b in (9,10,13)) / len(dec)
        if best is None or pr > best[1]:
            best = (k, pr)
    print('   best single-byte xor: key=%#x printable_ratio=%.3f sample=%r' % (best[0], best[1], bytes(b ^ best[0] for b in d[:60])))
