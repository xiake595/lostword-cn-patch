import os, sys, glob, time
root = r'D:\Codex_Project\Lostword\work\dev-cache'
files = glob.glob(os.path.join(root, '*', '*', '__data'))
print('files', len(files))
pats = {
    'Completed Errands': None, 'Complete All': None, 'Time Required': None,
    'Errand': None, 'Exchange': None, 'Exp': None, 'Daily': None, 'Limited': None,
}
hits = {}
t0 = time.time()
for f in files:
    try:
        with open(f, 'rb') as fh:
            d = fh.read()
    except Exception:
        continue
    found = {}
    for p in pats:
        b = p.encode()
        c = d.count(b)
        if c:
            found[p] = c
    if found:
        hits[f] = found
print('elapsed', round(time.time()-t0,1), 'files with hits', len(hits))
for p in pats:
    print('=== pattern', p)
    lst = [(f, h[p]) for f, h in hits.items() if p in h]
    lst.sort(key=lambda x: -x[1])
    for f, c in lst[:8]:
        print('   ', c, f.replace(root + os.sep, ''))
