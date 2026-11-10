import UnityPy, os, sys, time
path = r'D:\Codex_Project\Lostword\work\dev-cache\058ca74ee3b190798624c697eda9144d\db0b1194b37961915dbd1b969e3a2065\__data'
t0 = time.time()
env = UnityPy.load(path)
print('loaded in', round(time.time()-t0, 2))
objs = list(env.objects)
print('objects', len(objs))
for o in objs[:40]:
    try:
        name = ''
        if hasattr(o, 'read'):
            data = o.read()
            name = getattr(data, 'm_Name', '') or ''
        print(o.type.name, repr(name)[:80])
    except Exception as e:
        print(o.type.name, 'read fail', repr(e))
