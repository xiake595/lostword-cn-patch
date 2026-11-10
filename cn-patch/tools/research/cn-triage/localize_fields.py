import UnityPy, json
p = r'D:\Codex_Project\Lostword\work\dev-cache\218d248860d4e311e25b70b6497334d4\5833fefffd29a78acc4f52e91fcb2ece\__data'
env = UnityPy.load(p)

def go_path(go_pptr):
    try:
        names = []
        cur = go_pptr
        seen = 0
        while cur is not None and seen < 10:
            g = cur.read()
            names.append(getattr(g, 'm_Name', '?'))
            tf = getattr(g, 'm_Transform', None)
            cur = getattr(tf, 'm_Father', None) if tf is not None else None
            seen += 1
        return '/'.join(reversed(names))
    except Exception as e:
        return '?'

for o in env.objects:
    if o.type.name != 'MonoBehaviour':
        continue
    try:
        d = o.read()
    except Exception:
        continue
    t = getattr(d, 'm_Text', None)
    if isinstance(t, str) and t in ('Completed Errands', 'Remaining:', 'Cost', 'There are no Limited Errands available.'):
        print('=====', repr(t), 'path_id', o.path_id)
        try:
            print('  go path:', go_path(d.m_GameObject))
        except Exception:
            pass
        try:
            tree = d.object_reader.read_typetree()
            print('  tree keys:', list(tree.keys()))
            print('  full:', json.dumps(tree, ensure_ascii=False)[:1200])
        except Exception as e:
            print('  tree err', repr(e))
