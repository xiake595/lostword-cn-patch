import zipfile, os, sys, collections
pats = {
 'Completed Errands': None, 'Errands': None, 'Errand': None,
 'Remaining Time': None, 'Remaining': None,
 '派遣': None, '剩余时间': None, '剩余時間': None, '一键完成': None, '一鍵完成': None,
 '每日': None, '临时': None, '臨時': None, '已完成': None,
 '在太阳花田开音乐会': None, '太阳花田': None,
}
def scan_zip(path, label, max_report=40):
    print('=====', label, os.path.basename(path))
    try:
        z = zipfile.ZipFile(path)
    except Exception as e:
        print('  cannot open', e); return
    found = collections.defaultdict(list)
    for info in z.infolist():
        if info.file_size > 60*1024*1024:  # skip huge libs
            pass
        try:
            data = z.read(info.filename)
        except Exception:
            continue
        for p in pats:
            for enc in ('utf-8', 'utf-16-le'):
                b = p.encode(enc)
                c = data.count(b)
                if c:
                    found[p].append((info.filename, enc, c))
    for p, hits in found.items():
        # dedupe by entry
        seen = {}
        for n, enc, c in hits:
            seen.setdefault(n, set()).add(enc)
        print('  PAT', repr(p), '-> entries', len(seen))
        for n, encs in list(seen.items())[:6]:
            print('      ', n, sorted(encs))
    uns = [p for p in pats if p not in found]
    print('  no-hit patterns:', uns)

scan_zip(r'D:\Codex_Project\Lostword\integrated\assets\lwlocal.zip', 'CN patch data')
scan_zip(r'D:\Codex_Project\Lostword\integrated\apk\base.apk', 'game base.apk')
scan_zip(r'D:\Codex_Project\Lostword\integrated\apk\split_arm64.apk', 'game split')
