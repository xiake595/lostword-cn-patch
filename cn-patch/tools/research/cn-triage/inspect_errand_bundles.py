import UnityPy, os, glob, re
root = r'D:\Codex_Project\Lostword\work\dev-cache'
# bundles containing raw "Errand"
cands = []
for f in glob.glob(os.path.join(root, '*', '*', '__data')):
    d = open(f, 'rb').read()
    if b'Errand' in d:
        cands.append(f)
print('candidates', len(cands))
kw = re.compile(r'(errand|complete|time|exp|dispatch|daily|limited|remain)', re.I)
for f in cands:
    print('=====', f.replace(root + os.sep, ''))
    try:
        env = UnityPy.load(f)
    except Exception as e:
        print('  load fail', repr(e)); continue
    names = []
    for o in env.objects:
        try:
            if o.type.name in ('GameObject', 'MonoBehaviour', 'Texture2D', 'Sprite', 'TextAsset', 'MonoScript'):
                data = o.read()
                n = getattr(data, 'm_Name', '') or ''
                if n and kw.search(n):
                    names.append((o.type.name, n))
        except Exception:
            continue
    print('  keyword names', names[:20], 'total', len(names))
