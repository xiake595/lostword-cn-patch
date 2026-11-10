import os, glob, time
root = r'D:\Codex_Project\Lostword\work\dev-cache'
files = sorted(glob.glob(os.path.join(root, '*', '*', '__data')))
needles = ['ERRAND_TITLE', 'APP_ERRAND', 'APP_HOME_ERRAND', 'ErrandCountText', 'Completed', 'Complete All',
           'Time Required', 'Total Errands', 'DISPATCH', 'Dispatch']
hits = {n: [] for n in needles}
t0 = time.time()
for f in files:
    try:
        d = open(f, 'rb').read()
    except Exception:
        continue
    for n in needles:
        c = d.count(n.encode())
        if c:
            hits[n].append((f.replace(root + os.sep, ''), c))
print('elapsed', round(time.time()-t0,1))
for n in needles:
    lst = sorted(hits[n], key=lambda x: -x[1])[:8]
    print('===', n, 'files', len(hits[n]))
    for x in lst: print('   ', x)
