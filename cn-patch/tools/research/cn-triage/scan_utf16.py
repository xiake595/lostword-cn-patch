import os, glob, time, zipfile
root = r'D:\Codex_Project\Lostword\work\dev-cache'
needles = {}
for s in ['Completed Errands', 'Complete All', 'Time Required', 'Errand', 'Exp']:
    needles[s + ' [utf8]'] = s.encode('utf-8')
    needles[s + ' [utf16le]'] = s.encode('utf-16-le')
files = glob.glob(os.path.join(root, '*', '*', '__data'))
print('scan', len(files), 'bundle files')
hits = {k: [] for k in needles}
t0 = time.time()
for f in files:
    try:
        d = open(f, 'rb').read()
    except Exception:
        continue
    for k, b in needles.items():
        c = d.count(b)
        if c:
            hits[k].append((f.replace(root + os.sep, ''), c))
print('elapsed', round(time.time()-t0,1))
for k in needles:
    lst = sorted(hits[k], key=lambda x: -x[1])[:6]
    print('===', k, 'files', len(hits[k]), lst)
# also base apk entries
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\apk\base.apk')
print('=== base.apk entries')
for info in z.infolist():
    try:
        d = z.read(info.filename)
    except Exception:
        continue
    for k, b in needles.items():
        if k.endswith('[utf16le]'):
            continue
        c = d.count(b)
        if c:
            print('  ', info.filename, k, c)
