import os, glob, zipfile
root = r'D:\Codex_Project\Lostword\work\dev-cache'
files = sorted(glob.glob(os.path.join(root, '*', '*', '__data')))
needles = ['ErrandCell', 'NeedTime', 'ErrandPage', 'CompleteAll', 'CompleteAllButton', 'DepertureCount', 'AppearTime']
hits = {n: [] for n in needles}
for f in files:
    d = open(f, 'rb').read()
    for n in needles:
        c = d.count(n.encode())
        if c: hits[n].append((f.replace(root+os.sep,''), c))
for n in needles:
    print('===', n)
    for x in sorted(hits[n], key=lambda y: -y[1])[:6]:
        print('   ', x)
