import UnityPy, os, re, json
root = r'D:\Codex_Project\Lostword\work\dev-cache'
bundles = {
 'errand_screen': os.path.join(root, '218d248860d4e311e25b70b6497334d4', '5833fefffd29a78acc4f52e91fcb2ece', '__data'),
 'errand_sprites': os.path.join(root, '68be50648b14ed216c41d4e291a9aef3', '3c1e0faf251763b56b30a2ccd2de4027', '__data'),
}
for label, path in bundles.items():
    print('=====', label, path)
    env = UnityPy.load(path)
    names = {'Texture2D': [], 'Sprite': [], 'GameObject': [], 'TextAsset': [], 'MonoBehaviour': 0}
    texts = []
    for o in env.objects:
        try:
            tn = o.type.name
            if tn in names:
                data = o.read()
                n = getattr(data, 'm_Name', '') or ''
                if tn in ('Texture2D','Sprite','GameObject','TextAsset'):
                    names[tn].append(n)
                if tn == 'MonoBehaviour':
                    names[tn] += 1
                    # try to find string lists in raw
                    raw = getattr(data, 'm_Text', None)
                    if isinstance(raw, str) and raw:
                        texts.append(raw)
        except Exception:
            continue
    for k, v in names.items():
        if k == 'MonoBehaviour':
            print(' ', k, v)
        else:
            print(' ', k, len(v), v[:60])
    print('  mono texts sample', texts[:10])
