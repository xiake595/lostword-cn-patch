import os, glob, sys, time
sys.path.insert(0, r'D:\Codex_Project\Lostword\work\cn-triage')
# load extract() from debug_bundle3 (top part)
src = open(r'D:\Codex_Project\Lostword\work\cn-triage\debug_bundle3.py', encoding='utf-8').read()
ns = {}
exec(src.split("z = zipfile.ZipFile")[0], ns)
extract = ns['extract']

root = r'D:\Codex_Project\Lostword\work\dev-cache'
outdir = r'D:\Codex_Project\Lostword\work\dev-cache\extracted_hits'
os.makedirs(outdir, exist_ok=True)
files = sorted(glob.glob(os.path.join(root, '*', '*', '__data')))
needles = {}
for s in ['Completed Errands', 'Complete All', 'Time Required', 'Errand', 'Daily', 'Limited',
          'APP_ERRAND', 'ERRAND_TITLE', 'enText', 'm_Text']:
    needles[s] = s.encode('utf-8')
print('bundles', len(files), flush=True)
fails = 0; hits = []
t0 = time.time()
for idx, f in enumerate(files):
    try:
        d = open(f, 'rb').read()
        r = extract(d)
        data = r['data']
    except Exception as e:
        fails += 1
        if fails <= 10:
            print('FAIL', f, repr(e), flush=True)
        continue
    found = [(k, data.count(b)) for k, b in needles.items() if data.count(b)]
    if found:
        rel = f.replace(root + os.sep, '').replace(os.sep, '_')
        open(os.path.join(outdir, rel + '.raw'), 'wb').write(data)
        hits.append((f, found))
        print('HIT', f, found, flush=True)
    if (idx + 1) % 500 == 0:
        print('progress', idx + 1, 'hits', len(hits), 'fails', fails,
              'elapsed', round(time.time() - t0, 1), flush=True)
print('DONE files', len(files), 'hits', len(hits), 'fails', fails, 'elapsed', round(time.time() - t0, 1), flush=True)
