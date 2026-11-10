import UnityPy, os, zipfile, collections, json
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
tmp = r'D:\Codex_Project\Lostword\work\cn-triage\tmp_patch'
for key in ['21e07ccb3d64e00380cece3daed7b29d', 'a829a9cf3036a540bef3a3748c03061d', 'ce3dd200cc7efd8004cd6c4de8d3cddb']:
    n = [x for x in z.namelist() if key in x][0]
    p = os.path.join(tmp, key + '.bundle')
    open(p, 'wb').write(z.read(n))
    env = UnityPy.load(p)
    types = collections.Counter(o.type.name for o in env.objects)
    print('==', key, len(z.read(n)), dict(types))
    # find object names / script names containing Errand/Text
    shown = 0
    for o in env.objects:
        try:
            if o.type.name in ('GameObject', 'MonoScript'):
                d = o.read()
                nm = getattr(d, 'm_Name', '') or ''
                if nm and ('rrand' in nm or 'ext' in nm or 'Daily' in nm or 'Limit' in nm):
                    print('   ', o.type.name, nm)
                    shown += 1
        except Exception:
            continue
        if shown > 12: break
