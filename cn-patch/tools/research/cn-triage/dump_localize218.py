import UnityPy, json
p = r'D:\Codex_Project\Lostword\work\dev-cache\218d248860d4e311e25b70b6497334d4\5833fefffd29a78acc4f52e91fcb2ece\__data'
env = UnityPy.load(p)

def go_name(pptr):
    try:
        return getattr(pptr.read(), 'm_Name', '') or ''
    except Exception:
        return '?'

def hierarchy(go_pptr):
    names = []
    cur = go_pptr
    for _ in range(20):
        if cur is None:
            break
        try:
            go = cur.read()
        except Exception:
            break
        names.append(getattr(go, 'm_Name', '?') or '?')
        tr = getattr(go, 'm_Transform', None)
        if tr is None:
            break
        try:
            t = tr.read()
            fa = getattr(t, 'm_Father', None)
            if fa is None:
                break
            cur = getattr(fa.read(), 'm_GameObject', None)
        except Exception:
            break
    return '/'.join(reversed(names))

rows = []
for o in env.objects:
    if o.type.name != 'MonoBehaviour':
        continue
    try:
        d = o.read()
    except Exception:
        continue
    keys = None
    try:
        keys = set(d.object_reader.read_typetree().keys())
    except Exception:
        pass
    if not keys or 'enText' not in keys:
        continue
    rows.append({
        'path': hierarchy(d.m_GameObject),
        'm_Text': getattr(d, 'm_Text', ''),
        'enText': getattr(d, 'enText', ''),
        'jpText': getattr(d, 'jpText', ''),
        'showingLanguage': getattr(d, 'showingLanguage', None),
        'isFixedText': getattr(d, 'isFixedText', None),
    })
print('LocalizeText count', len(rows))
for r in rows:
    print(json.dumps(r, ensure_ascii=False))
