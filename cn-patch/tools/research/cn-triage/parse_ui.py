import re, sys
p = r'D:\Codex_Project\Lostword\work\cn-triage\ui.xml'
d = open(p, encoding='utf-8', errors='replace').read()
for m in re.finditer(r'text="([^"]*)"[^>]*bounds="([^"]*)"', d):
    if m.group(1):
        print(repr(m.group(1)), m.group(2))
