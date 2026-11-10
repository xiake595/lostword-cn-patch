import UnityPy, json
p = r'D:\Codex_Project\Lostword\work\dev-cache\218d248860d4e311e25b70b6497334d4\5833fefffd29a78acc4f52e91fcb2ece\__data'
env = UnityPy.load(p)
found = 0
for o in env.objects:
    if o.type.name != 'MonoBehaviour':
        continue
    try:
        d = o.read()
    except Exception:
        continue
    if getattr(d, 'm_Text', '') == 'Completed Errands':
        found += 1
        print('=== object', o.path_id, 'script', getattr(getattr(d, 'm_Script', None), 'read', lambda: None)())
        try:
            tt = d.object_reader.type_tree
            nodes = tt.nodes
            print('typetree nodes count', len(nodes))
            for i, n in enumerate(nodes):
                if n[1] == 1:
                    print('   ', i, n[0], 'type=string')
        except Exception as e:
            print('tt err', repr(e))
        try:
            tree = d.object_reader.read_typetree()
            print('tree', json.dumps(tree, ensure_ascii=False)[:600])
        except Exception as e:
            print('read tree err', repr(e))
        break
print('found', found)
