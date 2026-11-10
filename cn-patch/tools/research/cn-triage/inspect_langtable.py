import zipfile, re
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\apk\base.apk')
name = 'assets/bin/Data/1b4d15f3d50224726ac2a1153b296cca'
d = z.read(name)
print('size', len(d), 'head', d[:32])
# printable text extraction: asset may be serialized file with raw text blob
text = d.decode('utf-8', 'replace')
# find rows: KEY,japanese,english,...
rows = re.findall(r'([A-Z][A-Z0-9_]{4,})\s*,\s*([^\n]*?)\s*,\s*([^\n]*?)\s*,', text)
print('rows parsed', len(rows))
errand = [r for r in rows if 'ERRAND' in r[0] or 'errand' in r[2].lower() or 'Errand' in r[2]]
print('errand rows', len(errand))
for r in errand[:40]:
    print('KEY=%s | JP=%s | EN=%s' % (r[0][:60], r[1][:60], r[2][:90]))
# keys count
keys = set(r[0] for r in rows)
print('unique keys', len(keys))
print('sample keys', list(keys)[:10])
# look for 'Completed'
for m in re.finditer(r'Completed[^\n,]{0,80}', text):
    print('COMPLETED:', m.group(0)[:100])
