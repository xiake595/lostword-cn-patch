import UnityPy, zipfile, os, json
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
tmp = r'D:\Codex_Project\Lostword\work\cn-triage\tmp_patch'
os.makedirs(tmp, exist_ok=True)
keys = ['21e07ccb3d64e00380cece3daed7b29d', 'a829a9cf3036a540bef3a3748c03061d',
        'ce3dd200cc7efd8004cd6c4de8d3cddb', '3066f5fe466029404f72d3ca9b8afb2b',
        'a58687fbef7f89e1ce12823d4a232e73']

def hierarchy(go_pptr):
    names = []
    cur = go_pptr
    for _ in range(20):
        if cur is None: break
        try: go = cur.read()
        except Exception: break
        names.append(getattr(go, 'm_Name', '?') or '?')
        tr = None
        try:
            for c in (getattr(go, 'm_Component', []) or []):
                pptr = getattr(c, 'component', None)
                if pptr is None: continue
                try: obj = pptr.read()
                except Exception: continue
                if hasattr(obj, 'm_Children'): tr = pptr; break
        except Exception: pass
        if tr is None: break
        try:
            t = tr.read(); fa = getattr(t, 'm_Father', None)
            if fa is None: break
            cur = getattr(fa.read(), 'm_GameObject', None)
        except Exception: break
    return '/'.join(reversed(names))

for key in keys:
    names = [n for n in z.namelist() if key in n]
    if not names:
        print('==', key, 'NOT IN PATCH'); continue
    data = z.read(names[0])
    path = os.path.join(tmp, key + '.bundle')
    open(path, 'wb').write(data)
    print('==', key, 'patch bundle', len(data))
    env = UnityPy.load(path)
    shown = 0
    for o in env.objects:
        if o.type.name != 'MonoBehaviour':
            continue
        try:
            d = o.read()
            tree = d.object_reader.read_typetree()
        except Exception:
            continue
        if 'enText' not in tree: continue
        mt = tree.get('m_Text', '') or ''
        et = tree.get('enText', '') or ''
        if '剩余' in mt or '剩余' in et or '时间' in mt:
            print('   ', json.dumps({'path': hierarchy(d.m_GameObject), 'm_Text': mt, 'enText': et, 'jpText': tree.get('jpText')}, ensure_ascii=False))
            shown += 1
    print('   shown', shown)
