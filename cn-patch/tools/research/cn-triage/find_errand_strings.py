import json, os, zipfile, sys
base = r'D:\Codex_Project\Lostword\work\cn-analysis'
# 1) il2cpp string literals
sl = os.path.join(base, 'il2cpp-out', 'stringliteral.json')
try:
    data = json.load(open(sl, encoding='utf-8'))
    print('stringliteral count', len(data))
    keys = ['Completed Errands', 'Errand', 'Errands', 'Exp', '剩余时间', '派遣', '每日', '临时', '一键完成']
    for k in keys:
        hits = [d for d in data if k.lower() in str(d.get('value','')).lower()]
        print('LIT', repr(k), 'hits', len(hits))
        for h in hits[:5]: print('    ', h)
except Exception as e:
    print('stringliteral err', e)
# 2) raw metadata grep
md = os.path.join(base, 'base.apk__assets_bin_Data_Managed_Metadata_global-metadata.dat')
if not os.path.exists(md):
    # fallback: find any global-metadata.dat
    for root,dirs,files in os.walk(base):
        for f in files:
            if f.endswith('global-metadata.dat'):
                md = os.path.join(root,f); break
print('metadata', md, os.path.exists(md))
if os.path.exists(md):
    d = open(md,'rb').read()
    for s in ['Completed Errands','Errand','Errands','Exp','派遣','剩余时间','一键完成','每日','临时']:
        for enc in ('utf-8','utf-16-le'):
            b = s.encode(enc)
            print('MD', repr(s), enc, d.count(b))
