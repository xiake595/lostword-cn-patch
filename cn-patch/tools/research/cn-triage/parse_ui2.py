import re
for name in ('ui.xml','ui2.xml'):
    p = r'D:\Codex_Project\Lostword\work\cn-triage\%s' % name
    try:
        d = open(p, encoding='utf-8', errors='replace').read()
    except FileNotFoundError:
        continue
    print('===', name, len(d))
    for m in re.finditer(r'text="([^"]*)"[^>]*bounds="([^"]*)"', d):
        if m.group(1):
            print(repr(m.group(1)), m.group(2))
    print('bounds all:', re.findall(r'bounds="([^"]*)"', d)[:20])
