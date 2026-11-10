import os, glob, sys, time
src = open(r'D:\Codex_Project\Lostword\work\cn-triage\debug_bundle3.py', encoding='utf-8').read()
ns = {}
exec(src.split("z = zipfile.ZipFile")[0], ns)
extract = ns['extract']
root = r'D:\Codex_Project\Lostword\work\dev-cache'
outdir = r'D:\Codex_Project\Lostword\work\dev-cache\extract_hits2'
os.makedirs(outdir, exist_ok=True)
files = sorted(glob.glob(os.path.join(root, '*', '*', '__data')))
needles = {'Completed Errands': 'Completed Errands', 'Complete All': 'Complete All',
           'Time Required': 'Time Required', 'Total Errands': 'Total Errands',
           'Errand': 'Errand', 'ERRAND_TITLE': 'ERRAND_TITLE'}
targets = [needles[k] for k in ('Completed Errands', 'Complete All', 'Time Required', 'Total Errands', 'ERRAND_TITLE')]
fails = 0; hitfiles = 0
t0 = time.time()
log = open(r'D:\Codex_Project\Lostword\work\cn-triage\scan_official_deep2.log', 'w', encoding='utf-8')
for idx, f in enumerate(files):
    try:
        data = open(f, 'rb').read()
        r = extract(data)
        d = r['data']
    except Exception as e:
        fails += 1
        continue
    found = {k: d.count(k.encode()) for k in targets if d.count(k.encode())}
    if found:
        hitfiles += 1
        rel = f.replace(root + os.sep, '').replace(os.sep, '_')
        open(os.path.join(outdir, rel + '.raw'), 'wb').write(d)
        msg = f'HIT {f} {found}'
        print(msg, flush=True); log.write(msg + '\n')
    if (idx+1) % 1000 == 0:
        msg = f'progress {idx+1}/{len(files)} hitfiles={hitfiles} fails={fails} t={round(time.time()-t0,1)}'
        print(msg, flush=True); log.write(msg + '\n')
msg = f'DONE files={len(files)} hitfiles={hitfiles} fails={fails} elapsed={round(time.time()-t0,1)}'
print(msg, flush=True); log.write(msg + '\n'); log.flush(); log.close()
