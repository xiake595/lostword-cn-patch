import UnityPy, os, json, zipfile
root = r'D:\Codex_Project\Lostword\work\dev-cache'
bundles = {
 '3066f5fe466029404f72d3ca9b8afb2b': os.path.join(root, '3066f5fe466029404f72d3ca9b8afb2b', '3f29d3cab15de0050038221fce6376ca', '__data'),
 '16b3458c8d4b52b24e8a606c98c6bb17': os.path.join(root, '16b3458c8d4b52b24e8a606c98c6bb17', '94f609d9c4eb2252dd2029442d29a082', '__data'),
}
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
names = z.namelist()

def obj_name(o):
    try:
        d = o.read(); return getattr(d, 'm_Name', '') or ''
    except Exception: return ''

for label, p in bundles.items():
    print('=====', label)
    env = UnityPy.load(p)
    scripts = set(); monos = []
    for o in env.objects:
        try:
            if o.type.name == 'MonoScript':
                s = o.read()
                scripts.add(getattr(s, 'm_ClassName', '') or getattr(s, 'm_Name', ''))
            elif o.type.name == 'MonoBehaviour':
                d = o.read()
                go = getattr(d, 'm_GameObject', None)
                goname = obj_name(go) if go is not None else ''
                sc = getattr(d, 'm_Script', None)
                scname = ''
                if sc is not None:
                    s = sc.read(); scname = getattr(s, 'm_ClassName', '') or getattr(s, 'm_Name', '')
                vals = {}
                for attr in ('m_Text', 'm_text'):
                    v = getattr(d, attr, None)
                    if isinstance(v, str) and v:
                        vals[attr] = v
                if vals:
                    monos.append((scname, goname, vals))
        except Exception:
            continue
    print(' scripts', sorted(s for s in scripts if s)[:25])
    for m in monos[:40]:
        print('  ', m)
    key = label
    print(' in patch:', [n for n in names if key in n] or 'NO')
