import UnityPy, os, json
p = r'D:\Codex_Project\Lostword\work\dev-cache\218d248860d4e311e25b70b6497334d4\5833fefffd29a78acc4f52e91fcb2ece\__data'
env = UnityPy.load(p)
rows = []
for o in env.objects:
    if o.type.name != 'MonoBehaviour':
        continue
    try:
        d = o.read()
    except Exception:
        continue
    # collect readable string attrs
    vals = {}
    for attr in ('m_Name', 'm_Text', 'm_text', 'text', 'm_TextJP', 'm_TextEN', 'm_String', 'Key', 'key'):
        v = getattr(d, attr, None)
        if isinstance(v, str) and v:
            vals[attr] = v
    # scan typetree names for string fields
    try:
        tt = d.object_reader.type_tree
        for node in tt.nodes:
            if node[1] == 1 and len(node) > 2:  # string type
                pass
    except Exception:
        pass
    if vals:
        rows.append(vals)
print('mono with strings', len(rows))
for r in rows[:60]:
    print(r)
