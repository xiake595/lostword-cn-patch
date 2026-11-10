import UnityPy, os, json, collections
p = r'D:\Codex_Project\Lostword\work\cn-triage\tmp_patch\21e07ccb3d64e00380cece3daed7b29d.bundle'
env = UnityPy.load(p)
classes = collections.Counter()
for o in env.objects:
    if o.type.name == 'MonoScript':
        try:
            d = o.read()
            classes[getattr(d, 'm_ClassName', '') or getattr(d, 'm_Name', '')] += 1
        except Exception:
            pass
print('MonoScript classes:', dict(classes))
# sample one MonoBehaviour typetree
cnt = 0
for o in env.objects:
    if o.type.name != 'MonoBehaviour':
        continue
    try:
        d = o.read()
        tree = d.object_reader.read_typetree()
    except Exception:
        continue
    print('sample tree keys:', list(tree.keys())[:20])
    print('sample values:', json.dumps({k: v for k, v in tree.items() if isinstance(v, (str, int, float))}, ensure_ascii=False)[:400])
    cnt += 1
    if cnt >= 3: break
