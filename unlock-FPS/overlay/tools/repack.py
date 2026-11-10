"""
repack.py -- rebuild the APK from the two original archives without re-encoding
anything that Android is picky about.

  * every entry keeps its original compression method (resources.arsc and the
    dex files stay STORED, which targetSdk>=30 requires)
  * the manifest and our classes3.dex are swapped in
  * lib/arm64-v8a/* comes from the ABI split, so the result installs as a
    single standalone APK (no split install, no adb)

Usage:
    python repack.py BASE.apk SPLIT.apk MANIFEST DEX OUT.apk [ICON_PNG] [-arsc PATH]

ICON_PNG (optional) is stored as assets/tlw_icon.png. assets/ is used instead of
res/drawable because adding a drawable would force resources.arsc to be
re-encoded, which this pipeline deliberately avoids.

-arsc PATH (optional) swaps in a byte-patched resources.arsc. Only used by the
side-by-side build, where the app package name inside the resource table has to
match the renamed manifest; the bytes stay the same length, so nothing is
re-encoded either.
"""

import os
import sys
import zipfile


def entry_info(zf, name):
    return zf.getinfo(name)


def main(argv):
    arsc_p = None
    if "-arsc" in argv:
        i = argv.index("-arsc")
        if i + 1 >= len(argv):
            print(__doc__)
            return 2
        arsc_p = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]

    if len(argv) not in (6, 7):
        print(__doc__)
        return 2
    base_p, split_p, manifest_p, dex_p, out_p = argv[1:6]
    icon_p = argv[6] if len(argv) == 7 else None

    manifest = open(manifest_p, "rb").read()
    dex = open(dex_p, "rb").read()
    arsc = open(arsc_p, "rb").read() if arsc_p else None
    icon = None
    if icon_p and os.path.isfile(icon_p):
        icon = open(icon_p, "rb").read()

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
    zi = zipfile.ZipInfo("AndroidManifest.xml", date_time=(1981, 1, 1, 1, 1, 2))
    zi.compress_type = zipfile.ZIP_STORED
    out.writestr(zi, manifest)

    zi = zipfile.ZipInfo("classes3.dex", date_time=(1981, 1, 1, 1, 1, 2))
    zi.compress_type = zipfile.ZIP_STORED
    out.writestr(zi, dex)

    if icon is not None:
        zi = zipfile.ZipInfo("assets/tlw_icon.png", date_time=(1981, 1, 1, 1, 1, 2))
        zi.compress_type = zipfile.ZIP_DEFLATED
        out.writestr(zi, icon)
        print("icon -> assets/tlw_icon.png (%d bytes)" % len(icon))

    out.close()
    print("wrote %s" % out_p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
