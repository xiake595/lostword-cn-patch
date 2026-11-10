import zipfile, os, glob
z = zipfile.ZipFile(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip')
names = z.namelist()
root = r'D:\Codex_Project\Lostword\work\dev-cache'
keys = ['218d248860d4e311e25b70b6497334d4','16b3458c8d4b52b24e8a606c98c6bb17','4b2fe288824a36d26a90c244417bb4fc',
        '8df5deee82aa5ccf71066fb3cca05917','c9e335d270d4149e535ed5ee72038d2f','ab27164e639230068852b7291ffda766',
        '058ca74ee3b190798624c697eda9144d','3066f5fe466029404f72d3ca9b8afb2b','4b1387615e5eb5fb164256d6feb97444',
        'a58687fbef7f89e1ce12823d4a232e73','dfb53e68d197c7e4e4ae06179851165d','68be50648b14ed216c41d4e291a9aef3',
        'ee65f6014f4a0ee554b90338daee1b1e','e862eb602242a16f2c43e2837cdbca01','f7d6121b26f584d52a997f75068ae515']
for k in keys:
    pm = [n for n in names if k in n]
    off = glob.glob(os.path.join(root, k, '*', '__data'))
    size = os.path.getsize(off[0]) if off else 0
    print(f'{k}  official={size}  in_patch={"YES" if pm else "NO"}')
