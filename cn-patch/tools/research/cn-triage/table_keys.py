import zipfile, re
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\apk\base.apk')
d = z.read('assets/bin/Data/1b4d15f3d50224726ac2a1153b296cca')
t = d.decode('utf-8','replace')
rows = re.findall(r'([A-Z][A-Z0-9_]{4,})\s*,\s*([^\n]*?)\s*,\s*([^\n]*?)\s*,', t)
for r in rows:
    k, jp, en = r
    if 'EXP' in k or 'COMPLETE' in k or 'ERRAND' in k or 'COUNT' in k:
        print(f'{k} | JP={jp[:40]} | EN={en[:60]}')
