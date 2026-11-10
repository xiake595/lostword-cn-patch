import sys, zipfile, os, re, collections
src = open(r'D:\Codex_Project\Lostword\work\cn-triage\debug_bundle3.py', encoding='utf-8').read()
ns = {}
exec(src.split("z = zipfile.ZipFile")[0], ns)
extract = ns['extract']

z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
names = [n for n in z.namelist() if n.startswith('lwlocal/bundles/')]
pats = [b'APP_ERRAND', b'Completed Errands', b'CompletedErrands', b'Errand',
        '派遣'.encode(), '一键完成'.encode(), '剩余时间'.encode()]
outdir = r'D:\Codex_Project\Lostword\work\cn-triage\bundles_raw'
os.makedirs(outdir, exist_ok=True)
hits = 0
for n in names:
    try:
        r = extract(z.read(n))
    except Exception as e:
        print('FAIL', n, repr(e)); continue
    d = r['data']
    found = [(p.decode('utf-8', 'replace'), d.count(p)) for p in pats if d.count(p)]
    if found:
        hits += 1
        print(f'{n} size={len(d)} found={found}')
        # dump any bundle that has localization-table-ish markers
        if any(p in d for p in (b'APP_ERRAND', b'Completed Errands', '派遣'.encode())):
            fn = os.path.join(outdir, n.split('/')[-3] + '__' + n.split('/')[-2] + '.raw')
            open(fn, 'wb').write(d)
print('bundles scanned', len(names), 'hits', hits)
print('dumped to', outdir)
