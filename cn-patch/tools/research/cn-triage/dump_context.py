import os, re, glob
outdir = r'D:\Codex_Project\Lostword\work\cn-triage\bundles_raw'
pats = [b'Errands', b'Errand', '派遣'.encode(), '剩余时间'.encode(), b'Completed', b'Finished', b'Exp\x00', b'>Exp<', b'EXP']
for p in sorted(glob.glob(os.path.join(outdir, '*.raw'))):
    d = open(p, 'rb').read()
    hits = 0
    for pat in pats:
        start = 0
        cnt = 0
        while True:
            i = d.find(pat, start)
            if i < 0: break
            cnt += 1
            if cnt <= 3:
                seg = d[max(0, i-80):i+120]
                print(os.path.basename(p), repr(pat), '@', i, repr(seg))
            start = i + len(pat)
        if cnt: hits += 1
    if hits: print('---')
