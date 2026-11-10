"""
clone.py -- rename the app so it can be installed next to the official one.

Only two files carry the package name:

    AndroidManifest.xml   6 x UTF-16LE
    resources.arsc        1 x UTF-16LE  (ResTable_package.name, a 128-char16
                                         field, not a string-pool index)

Both are patched IN PLACE with a same-length replacement, so the string pool
offsets, every chunk size and the fixed 128-char field all stay valid. That is
the entire point: this pipeline never re-encodes resources.arsc, and it does not
start here. A replacement name that is not exactly as long as the original is
rejected instead of silently corrupting the file.

The launcher label is a normal UTF-8 pool entry, so it gets the same treatment
(same byte length, or leave it alone).

Usage:
    python clone.py MANIFEST_IN MANIFEST_OUT ARSC_IN ARSC_OUT OLD_PKG NEW_PKG \
                    [OLD_LABEL NEW_LABEL]
"""

import sys


def patch(data, old, new, what, enc):
    o, n = old.encode(enc), new.encode(enc)
    if len(o) != len(n):
        raise SystemExit(
            "%s: replacement must be %d bytes, got %d (%r -> %r)"
            % (what, len(o), len(n), old, new))
    hits = data.count(o)
    if hits == 0:
        raise SystemExit("%s: %r not found" % (what, old))
    return data.replace(o, n), hits


def main(argv):
    if len(argv) not in (7, 9):
        print(__doc__)
        return 2

    man_in, man_out, arsc_in, arsc_out = argv[1:5]
    old_pkg, new_pkg = argv[5], argv[6]

    man = open(man_in, "rb").read()
    arsc = open(arsc_in, "rb").read()

    man, h1 = patch(man, old_pkg, new_pkg, "manifest package", "utf-16-le")
    arsc, h2 = patch(arsc, old_pkg, new_pkg, "resources.arsc package", "utf-16-le")
    print("package : %s -> %s" % (old_pkg, new_pkg))
    print("          manifest %d hit(s), resources.arsc %d hit(s)" % (h1, h2))

    if len(argv) == 9:
        old_lab, new_lab = argv[7], argv[8]
        arsc, h3 = patch(arsc, old_lab, new_lab, "application label", "utf-8")
        print("label   : %s -> %s (%d hit(s))" % (old_lab, new_lab, h3))

    open(man_out, "wb").write(man)
    open(arsc_out, "wb").write(arsc)
    print("wrote %s (%d bytes)" % (man_out, len(man)))
    print("wrote %s (%d bytes, unchanged size)" % (arsc_out, len(arsc)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
