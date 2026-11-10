import zipfile
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
names = z.namelist()
print('total entries', len(names))
for key in ['218d248860d4e311e25b70b6497334d4', '68be50648b14ed216c41d4e291a9aef3', 'ee65f6014f4a0ee554b90338daee1b1e', 'e862eb602242a16f2c43e2837cdbca01', '16b3458c8d4b52b24e8a606c98c6bb17', '058ca74ee3b190798624c697eda9144d']:
    hits = [n for n in names if key in n]
    print(key, '->', hits if hits else 'NOT IN PATCH')
# also list any entry whose path contains 'errand' in manifest.json
m = z.read('lwlocal/manifest.json').decode('utf-8', 'replace') if 'lwlocal/manifest.json' in names else ''
import re
hits = re.findall(r'[^"]*[Ee]rrand[^"]*', m)
print('manifest errand refs', len(hits), hits[:10])
