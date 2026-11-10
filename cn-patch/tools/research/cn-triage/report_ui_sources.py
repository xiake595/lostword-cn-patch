import UnityPy, json, zipfile, os
root = r'D:\Codex_Project\Lostword\work\dev-cache'
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
patch_names = z.namelist()

def in_patch(key):
    return key if any(key in n for n in patch_names) else 'NO'

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
            comps = getattr(go, 'm_Component', []) or []
            for c in comps:
                pptr = getattr(c, 'component', None)
                if pptr is None: continue
                try:
                    obj = pptr.read()
                except Exception:
                    continue
                if hasattr(obj, 'm_Children'):
                    tr = pptr; break
        except Exception:
            pass
        if tr is None: break
        try:
            t = tr.read()
            fa = getattr(t, 'm_Father', None)
            if fa is None: break
            cur = getattr(fa.read(), 'm_GameObject', None)
        except Exception:
            break
    return '/'.join(reversed(names))

bundles = {
 '218d248860d4e311e25b70b6497334d4': ('5833fefffd29a78acc4f52e91fcb2ece', None),
 '3066f5fe466029404f72d3ca9b8afb2b': ('3f29d3cab15de0050038221fce6376ca', None),
 '4b1387615e5eb5fb164256d6feb97444': ('c8c59aa3f809ab6936bced6d7d5d661a', None),
 'dfb53e68d197c7e4e4ae06179851165d': ('8772fb24a697cea37c79c402f804f1ea', None),
 'a58687fbef7f89e1ce12823d4a232e73': ('ea1be9b4cea168999b1acc29b35da18f', None),
 '058ca74ee3b190798624c697eda9144d': ('db0b1194b37961915dbd1b969e3a2065', None),
 '16b3458c8d4b52b24e8a606c98c6bb17': ('94f609d9c4eb2252dd2029442d29a082', None),
 '4b2fe288824a36d26a90c244417bb4fc': ('433e6b900789c65e87f6624d04038794', None),
 '8df5deee82aa5ccf71066fb3cca05917': ('fb6d4827c2b8a6f06ac9da5550ab4b0b', None),
 'c9e335d270d4149e535ed5ee72038d2f': ('af73690d8936a440dc308312f0da9d11', None),
}
targets = ['Completed Errands', 'Remaining:', 'Cost', 'There are no Limited Errands available.',
           'Time Required', 'Total Errands', 'Errand', 'Complete All']
for key, (b, _) in bundles.items():
    p = os.path.join(root, key, b, '__data')
    print('=====', key, 'in_patch=', in_patch(key))
    try:
        env = UnityPy.load(p)
    except Exception as e:
        print('  load fail', repr(e)); continue
    for o in env.objects:
        if o.type.name != 'MonoBehaviour':
            continue
        try:
            d = o.read()
            tree = d.object_reader.read_typetree()
        except Exception:
            continue
        if 'enText' not in tree:
            continue
        mt = tree.get('m_Text', '')
        if mt in targets:
            print('  ', json.dumps({'path': hierarchy(d.m_GameObject), 'm_Text': mt,
                                    'enText': tree.get('enText'), 'jpText': tree.get('jpText')}, ensure_ascii=False))
