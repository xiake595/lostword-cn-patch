import UnityPy, os, json
p = r'D:\Codex_Project\Lostword\work\dev-cache\218d248860d4e311e25b70b6497334d4\5833fefffd29a78acc4f52e91fcb2ece\__data'
env = UnityPy.load(p)

def obj_name(o):
    try:
        d = o.read()
        return getattr(d, 'm_Name', '') or ''
    except Exception:
        return ''

def mono_info(o):
    d = o.read()
    out = {}
    go = getattr(d, 'm_GameObject', None)
    if go is not None:
        try:
            out['go'] = obj_name(go)
        except Exception:
            out['go'] = '?'
    sc = getattr(d, 'm_Script', None)
    if sc is not None:
        try:
            s = sc.read()
            out['script'] = getattr(s, 'm_ClassName', '') or getattr(s, 'm_Name', '') or ''
        except Exception:
            out['script'] = '?'
    for attr in dir(d):
        if attr.startswith('m_') or attr in ('text', 'key', 'value'):
            try:
                v = getattr(d, attr)
            except Exception:
                continue
            if isinstance(v, str) and v and len(v) < 300:
                out[attr] = v
    return out

rows = []
for o in env.objects:
    if o.type.name != 'MonoBehaviour':
        continue
    try:
        info = mono_info(o)
    except Exception:
        continue
    if any(k not in ('go', 'script', 'm_Name', 'm_GameObject') for k in info):
        rows.append(info)
print('rows', len(rows))
for r in rows:
    print(json.dumps(r, ensure_ascii=False))
