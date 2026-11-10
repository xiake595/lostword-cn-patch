"""
repack.py -- rebuild the APK from the two original archives without re-encoding
anything that Android is picky about.

  * every entry keeps its original compression method (resources.arsc and the
    dex files stay STORED, which targetSdk>=30 requires)
  * the manifest and our classes3.dex are swapped in
  * extra assets can be streamed straight from disk (the CN data zip is 445 MB,
    so it is never read into memory)
  * lib/arm64-v8a/* comes from the ABI split, so the result installs as a
    single standalone APK (no split install, no adb)

Usage:
    python repack.py BASE.apk SPLIT.apk MANIFEST DEX OUT.apk [ICON_PNG] [-arsc PATH]
                     [-asset-store NAME=PATH]... [-asset NAME=PATH]...

ICON_PNG (optional) is stored as assets/tlw_icon.png. assets/ is used instead of
res/drawable because adding a drawable would force resources.arsc to be
re-encoded, which this pipeline deliberately avoids.

-arsc PATH (optional) swaps in a byte-patched resources.arsc.

-asset-store NAME=PATH adds an entry stored uncompressed (fast streaming reads
on device, and no 445 MB temporary copy while building).
-asset NAME=PATH adds an entry deflated.
"""

import os
import shutil
import sys
import zipfile

CHUNK = 4 * 1024 * 1024
FIXED_TIME = (1981, 1, 1, 1, 1, 2)


def add_streamed(out, name, path, compress_type):
    """write one APK entry from a file on disk, chunk by chunk."""
    zi = zipfile.ZipInfo(name, date_time=FIXED_TIME)
    zi.compress_type = compress_type
    size = os.path.getsize(path)
    with open(path, "rb") as src, out.open(zi, "w") as dst:
        shutil.copyfileobj(src, dst, CHUNK)
    print("asset -> %s (%d bytes%s)" % (name, size,
          "" if compress_type == zipfile.ZIP_STORED else ", deflated"))


def main(argv):
    arsc_p = None
    icon_p = None
    assets = []            # (name, path, compress_type)
    pos = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "-arsc":
            arsc_p = argv[i + 1]
            i += 2
        elif a in ("-asset", "-asset-store"):
            name, _, path = argv[i + 1].partition("=")
            if not name or not path:
                print(__doc__)
                return 2
            assets.append((name, path,
                           zipfile.ZIP_STORED if a == "-asset-store"
                           else zipfile.ZIP_DEFLATED))
            i += 2
        else:
            pos.append(a)
            i += 1

    if len(pos) < 5:
        print(__doc__)
        return 2
    base_p, split_p, manifest_p, dex_p, out_p = pos[:5]
    if len(pos) >= 6:
        icon_p = pos[5]

    manifest = open(manifest_p, "rb").read()
    dex = open(dex_p, "rb").read()
    arsc = open(arsc_p, "rb").read() if arsc_p else None

    out = zipfile.ZipFile(out_p, "w", allowZip64=True)
    written = set()

    with zipfile.ZipFile(base_p) as base, zipfile.ZipFile(split_p) as split:
        # 1) everything from base, minus signatures and the old manifest
        for info in base.infolist():
            n = info.filename
            if n.startswith("META-INF/") and n.split(".")[-1].upper() in ("RSA", "SF", "MF", "EC", "DSA"):
                continue
            if n == "AndroidManifest.xml":
                continue
            if n == "resources.arsc" and arsc is not None:
                # same slot, same compression, patched bytes
                zi = zipfile.ZipInfo(n, date_time=info.date_time)
                zi.compress_type = info.compress_type
                zi.external_attr = info.external_attr
                zi.internal_attr = info.internal_attr
                zi.create_system = info.create_system
                out.writestr(zi, arsc)
                written.add(n)
                continue
            if n in written:
                continue
            data = base.read(n)
            zi = zipfile.ZipInfo(n, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.internal_attr = info.internal_attr
            zi.create_system = info.create_system
            out.writestr(zi, data)
            written.add(n)

        # 2) native libs from the ABI split
        for info in split.infolist():
            n = info.filename
            if not n.startswith("lib/"):
                continue
            if n in written:
                continue
            data = split.read(n)
            zi = zipfile.ZipInfo(n, date_time=info.date_time)
            zi.compress_type = zipfile.ZIP_STORED     # so: keep .so mmap-friendly
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            out.writestr(zi, data)
            written.add(n)

    # 3) our own entries
    zi = zipfile.ZipInfo("AndroidManifest.xml", date_time=FIXED_TIME)
    zi.compress_type = zipfile.ZIP_STORED
    out.writestr(zi, manifest)

    zi = zipfile.ZipInfo("classes3.dex", date_time=FIXED_TIME)
    zi.compress_type = zipfile.ZIP_STORED
    out.writestr(zi, dex)

    if icon_p and os.path.isfile(icon_p):
        zi = zipfile.ZipInfo("assets/tlw_icon.png", date_time=FIXED_TIME)
        zi.compress_type = zipfile.ZIP_DEFLATED
        out.writestr(zi, open(icon_p, "rb").read())
        written.add("assets/tlw_icon.png")
        print("icon -> assets/tlw_icon.png")

    # 4) streamed extra assets (large files never enter memory)
    for name, path, ctype in assets:
        if name in written:
            print("skip duplicate asset %s" % name)
            continue
        add_streamed(out, name, path, ctype)
        written.add(name)

    out.close()
    print("wrote %s (%d entries)" % (out_p, len(written)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
