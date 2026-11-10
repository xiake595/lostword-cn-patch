import zipfile, re
def scan(path, label, pats, ctx=60, maxhits=12):
    print('=====', label)
    z = zipfile.ZipFile(path)
    for info in z.infolist():
        try:
            data = z.read(info.filename)
        except Exception:
            continue
        for p in pats:
            b = p.encode('utf-8')
            start = 0
            n = 0
            while True:
                i = data.find(b, start)
                if i < 0: break
                n += 1
                if n <= maxhits:
                    seg = data[max(0,i-ctx):i+len(b)+ctx]
                    print('  ', info.filename, '@', i, repr(seg))
                start = i + len(b)
    print(' done', label)

scan(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip', 'CN patch bundles (Completed)',
     ['Completed', 'COMPLETED', 'Complete'])
scan(r'D:\Codex_Project\Lostword\integrated\apk\base.apk', 'base.apk assets (Completed/Errand)',
     ['Completed Errands', 'Completed', 'Errand'], ctx=80, maxhits=6)
