"""
axml.py -- minimal, dependency-free AndroidManifest (AXML) editor.

Edits the compiled binary manifest in place, so resources.arsc is never
re-encoded and every other entry of the APK stays byte-identical.

CLI
    python axml.py add-provider  IN OUT  CLASS  AUTHORITY
    python axml.py add-perm      IN OUT  PERMISSION [PERMISSION ...]
    python axml.py drop-attr     IN OUT  ELEMENT ATTR [ELEMENT ATTR ...]
    python axml.py set-bool      IN OUT  ELEMENT ATTR VALUE [ELEMENT ATTR VALUE ...]
    python axml.py set-launcher  IN OUT  OLD_ACTIVITY NEW_ACTIVITY
    python axml.py dump          IN

Notes
  * strings are append-only, so existing indices stay valid
  * attribute values are typed; we only emit strings and booleans
  * no styles in an AndroidManifest string pool (asserted)
"""

import struct
import sys

RES_STRING_POOL = 0x0001
RES_XML = 0x0003
RES_XML_START_NS = 0x0100
RES_XML_END_NS = 0x0101
RES_XML_START_EL = 0x0102
RES_XML_END_EL = 0x0103
RES_XML_CDATA = 0x0104
RES_XML_RESOURCE_MAP = 0x0180

TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10
TYPE_INT_BOOLEAN = 0x12

NO_ENTRY = 0xFFFFFFFF


# --------------------------------------------------------------- string pool

class Pool:
    def __init__(self, data, off):
        (self.type, self.header_size, self.size) = struct.unpack_from("<HHI", data, off)
        (self.count, self.style_count, self.flags,
         self.strings_start, self.styles_start) = struct.unpack_from("<IIIII", data, off + 8)
        if self.style_count:
            raise SystemExit("styled string pool not supported")
        self.utf8 = (self.flags & 0x100) != 0
        self.offsets = list(struct.unpack_from("<%dI" % self.count, data, off + 28))
        self.strings = [self._read(data, off + self.strings_start + o) for o in self.offsets]

    def _read(self, data, p):
        if self.utf8:
            _, p = _varint(data, p)          # utf16 length, unused
            m, p = _varint(data, p)
            return data[p:p + m].decode("utf-8", "replace")
        n = struct.unpack_from("<H", data, p)[0]
        return data[p + 2:p + 2 + n * 2].decode("utf-16-le", "replace")

    def index(self, s):
        try:
            return self.strings.index(s)
        except ValueError:
            return -1

    def add(self, s):
        i = self.index(s)
        if i >= 0:
            return i
        self.strings.append(s)
        self.count += 1
        return self.count - 1

    def encode(self):
        body = bytearray()
        offsets = []
        for s in self.strings:
            offsets.append(len(body))
            if self.utf8:
                b = s.encode("utf-8")
                body += _putvarint(len(s)) + _putvarint(len(b)) + b + b"\x00"
            else:
                b = s.encode("utf-16-le")
                body += struct.pack("<H", len(s)) + b + b"\x00\x00"
        while len(body) % 4:
            body += b"\x00"

        header_size = 28
        strings_start = header_size + 4 * len(offsets)
        size = strings_start + len(body)
        out = struct.pack("<HHI", RES_STRING_POOL, header_size, size)
        out += struct.pack("<IIIII", len(offsets), 0, 0x100 if self.utf8 else 0, strings_start, 0)
        out += struct.pack("<%dI" % len(offsets), *offsets)
        out += body
        return out


def _varint(data, p):
    v = data[p]
    if v & 0x80:
        return ((v & 0x7F) << 8) | data[p + 1], p + 2
    return v, p + 1


def _putvarint(v):
    if v > 0x7F:
        return bytes([0x80 | ((v >> 8) & 0x7F), v & 0xFF])
    return bytes([v])


# -------------------------------------------------------------------- chunks

def chunks(data, start=8):
    p = start
    while p + 8 <= len(data):
        t, hs, sz = struct.unpack_from("<HHI", data, p)
        if sz < 8 or p + sz > len(data):
            break
        yield t, p, hs, sz
        p += sz


def read_element(data, p):
    # ResXMLTree_node: chunk header(8) + lineNumber(4) + comment(4) = 16
    # ResXMLTree_attrExt follows, so ns/name live at p+16
    ns, name = struct.unpack_from("<II", data, p + 16)
    (attr_start, attr_size, attr_count,
     _i, _c, _s) = struct.unpack_from("<HHHHHH", data, p + 24)
    attrs = []
    a = p + 16 + attr_start
    for _ in range(attr_count):
        ans, aname, raw = struct.unpack_from("<III", data, a)
        vsize, _r, dtype, dval = struct.unpack_from("<HBBI", data, a + 12)
        attrs.append({"ns": ans, "name": aname, "raw": raw, "type": dtype, "data": dval})
        a += attr_size
    return {"ns": ns, "name": name, "attrs": attrs}


def build_start(ns, name, attrs):
    attr_size = 20
    attr_start = 20
    size = 16 + attr_start + attr_size * len(attrs)
    out = struct.pack("<HHI", RES_XML_START_EL, 16, size)
    out += struct.pack("<II", 0xFFFFFFFF, 0xFFFFFFFF)     # lineNumber, comment
    out += struct.pack("<II", ns, name)
    out += struct.pack("<HHHHHH", attr_start, attr_size, len(attrs), 0, 0, 0)
    for a in attrs:
        raw = a["data"] if a["type"] == TYPE_STRING else NO_ENTRY
        out += struct.pack("<III", a["ns"], a["name"], raw)
        out += struct.pack("<HBBI", 8, 0, a["type"], a["data"])
    return out


def build_end(ns, name):
    return struct.pack("<HHIII", RES_XML_END_EL, 16, 24, 0xFFFFFFFF, 0xFFFFFFFF) + \
           struct.pack("<II", ns, name)


# --------------------------------------------------------------------- model

def load(path):
    data = open(path, "rb").read()
    magic, hsize, total = struct.unpack_from("<HHI", data, 0)
    if magic != RES_XML:
        raise SystemExit("not a compiled XML (AXML)")
    pool = None
    resmap = b""
    nodes = []
    for t, p, hs, sz in chunks(data):
        if t == RES_STRING_POOL:
            pool = Pool(data, p)
        elif t == RES_XML_RESOURCE_MAP:
            resmap = data[p:p + sz]
        elif t in (RES_XML_START_NS, RES_XML_END_NS, RES_XML_CDATA):
            nodes.append((t, data[p:p + sz]))
        elif t == RES_XML_START_EL:
            nodes.append((t, read_element(data, p)))
        elif t == RES_XML_END_EL:
            ns, name = struct.unpack_from("<II", data, p + 16)
            nodes.append((t, {"ns": ns, "name": name}))
        else:
            nodes.append((t, data[p:p + sz]))
    return pool, resmap, nodes


def save(path, pool, resmap, nodes):
    body = bytearray(pool.encode())
    if resmap:
        body += resmap
    for t, node in nodes:
        if t == RES_XML_START_EL:
            body += build_start(node["ns"], node["name"], node["attrs"])
        elif t == RES_XML_END_EL:
            body += build_end(node["ns"], node["name"])
        else:
            body += node
    out = bytearray(struct.pack("<HHI", RES_XML, 8, 8 + len(body))) + body
    open(path, "wb").write(out)
    return len(out)


# ------------------------------------------------------------------ commands

def android_ns(pool):
    i = pool.index("http://schemas.android.com/apk/res/android")
    if i < 0:
        raise SystemExit("android namespace missing")
    return i


def cmd_add_provider(src, dst, cls, authority):
    pool, resmap, nodes = load(src)
    ns = android_ns(pool)
    i_name = pool.index("name")
    i_auth = pool.index("authorities")
    i_exp = pool.index("exported")
    if min(i_name, i_auth, i_exp) < 0:
        raise SystemExit("required attribute names missing")

    i_cls = pool.add(cls)
    i_authv = pool.add(authority)
    i_prov = pool.index("provider")
    if i_prov < 0:
        i_prov = pool.add("provider")

    attrs = [
        {"ns": ns, "name": i_name, "type": TYPE_STRING, "data": i_cls},
        {"ns": ns, "name": i_auth, "type": TYPE_STRING, "data": i_authv},
        {"ns": ns, "name": i_exp, "type": TYPE_INT_BOOLEAN, "data": 0},
    ]

    # insert right before </application>
    depth = 0
    insert_at = None
    for idx, (t, node) in enumerate(nodes):
        if t == RES_XML_START_EL:
            depth += 1
        elif t == RES_XML_END_EL:
            depth -= 1
            if depth == 1 and pool.strings[node["name"]] == "application":
                insert_at = idx
                break
    if insert_at is None:
        raise SystemExit("</application> not found")

    nodes[insert_at:insert_at] = [
        (RES_XML_START_EL, {"ns": NO_ENTRY, "name": i_prov, "attrs": attrs}),
        (RES_XML_END_EL, {"ns": NO_ENTRY, "name": i_prov}),
    ]
    print("provider inserted at chunk %d" % insert_at)
    print("size: %d -> %d" % (len(open(src, "rb").read()), save(dst, pool, resmap, nodes)))


def cmd_drop_attr(src, dst, pairs):
    pool, resmap, nodes = load(src)
    ns = android_ns(pool)
    dropped = 0
    for el_name, at_name in pairs:
        i_el = pool.index(el_name)
        i_at = pool.index(at_name)
        if i_el < 0 or i_at < 0:
            print("  skip %s/%s (not present)" % (el_name, at_name))
            continue
        depth = 0
        for idx, (t, node) in enumerate(nodes):
            if t == RES_XML_START_EL:
                depth += 1
                if node["name"] == i_el:
                    before = len(node["attrs"])
                    node["attrs"] = [a for a in node["attrs"]
                                     if not (a["name"] == i_at and a["ns"] == ns)]
                    if len(node["attrs"]) != before:
                        dropped += before - len(node["attrs"])
                        print("  dropped %s/@%s" % (el_name, at_name))
            elif t == RES_XML_END_EL:
                depth -= 1
    print("total dropped: %d" % dropped)
    print("size: %d -> %d" % (len(open(src, "rb").read()), save(dst, pool, resmap, nodes)))


def cmd_set_bool(src, dst, triples):
    """set or add a boolean attribute; EL may be 'activity@android:name=CLASS'
    to target one specific activity instead of every element of that name"""
    pool, resmap, nodes = load(src)
    ns = android_ns(pool)
    i_name = pool.index("name")
    changed = 0
    for spec, at_name, val in triples:
        el_name, _, only = spec.partition("@")
        if only.startswith("android:name="):
            only = only[len("android:name="):]
        i_el = pool.index(el_name)
        i_at = pool.index(at_name)
        if i_el < 0:
            print("  skip <%s> (not present)" % el_name)
            continue
        if i_at < 0:
            i_at = pool.add(at_name)
        want = 1 if str(val).lower() in ("1", "true", "yes") else 0
        for (t, node) in nodes:
            if t != RES_XML_START_EL or node["name"] != i_el:
                continue
            if only:
                hit_name = False
                for a in node["attrs"]:
                    if a["name"] == i_name and a["ns"] == ns \
                            and a["type"] == TYPE_STRING \
                            and pool.strings[a["data"]] == only:
                        hit_name = True
                        break
                if not hit_name:
                    continue
            hit = False
            for a in node["attrs"]:
                if a["name"] == i_at and a["ns"] == ns:
                    a["type"] = TYPE_INT_BOOLEAN
                    a["data"] = want
                    hit = True
                    break
            if not hit:
                node["attrs"].append({"ns": ns, "name": i_at,
                                      "type": TYPE_INT_BOOLEAN, "data": want})
            changed += 1
            print("  <%s %s>/@%s = %s" % (el_name, only or "*", at_name,
                                          "true" if want else "false"))
    print("total changed: %d" % changed)
    print("size: %d -> %d" % (len(open(src, "rb").read()), save(dst, pool, resmap, nodes)))


def _attr_str(pool, ns, node, i_at):
    for a in node["attrs"]:
        if a["name"] == i_at and a["ns"] == ns and a["type"] == TYPE_STRING:
            return pool.strings[a["data"]]
    return None


def _element_ranges(nodes):
    """start index -> end index for every element (flat node list)."""
    stack = []
    out = {}
    for idx, (t, node) in enumerate(nodes):
        if t == RES_XML_START_EL:
            stack.append((idx, node["name"]))
        elif t == RES_XML_END_EL and stack:
            start, nm = stack.pop()
            if nm == node["name"]:
                out[start] = idx
    return out


def _direct_children(nodes, rng, start):
    """indices of the direct child START_EL nodes of the element at 'start'."""
    end = rng[start]
    kids = []
    depth = 1
    j = start + 1
    while j < end:
        t, node = nodes[j]
        if t == RES_XML_START_EL:
            depth += 1
            if depth == 2:
                kids.append(j)
        elif t == RES_XML_END_EL:
            depth -= 1
        j += 1
    return kids


def cmd_set_launcher(src, dst, old_activity, new_activity):
    """Move MAIN/LAUNCHER from OLD_ACTIVITY to a brand-new NEW_ACTIVITY.

    The old activity keeps everything else (including e.g. VIEW/BROWSABLE
    filters); only the intent-filter that carries both
    android.intent.action.MAIN and android.intent.category.LAUNCHER is
    removed.  The new activity gets a launcher filter and exported=true.
    """
    pool, resmap, nodes = load(src)
    ns = android_ns(pool)
    i_name = pool.index("name")
    if i_name < 0:
        raise SystemExit("'name' attribute missing from pool")

    i_act = pool.index("activity")
    i_filter = pool.index("intent-filter")
    i_action = pool.index("action")
    i_category = pool.index("category")
    if min(i_act, i_filter, i_action, i_category) < 0:
        raise SystemExit("activity/intent-filter/action/category missing")
    i_main = pool.add("android.intent.action.MAIN")
    i_launcher = pool.add("android.intent.category.LAUNCHER")

    rng = _element_ranges(nodes)

    # 1) find + remove the MAIN/LAUNCHER filter of the old activity
    targets = []
    for idx, (t, node) in enumerate(nodes):
        if t != RES_XML_START_EL or node["name"] != i_act:
            continue
        if _attr_str(pool, ns, node, i_name) != old_activity:
            continue
        for j in _direct_children(nodes, rng, idx):
            t2, n2 = nodes[j]
            if t2 != RES_XML_START_EL or n2["name"] != i_filter:
                continue
            has_main = has_launcher = False
            for k in _direct_children(nodes, rng, j):
                t3, n3 = nodes[k]
                if t3 != RES_XML_START_EL:
                    continue
                v = _attr_str(pool, ns, n3, i_name)
                if n3["name"] == i_action and v == "android.intent.action.MAIN":
                    has_main = True
                elif n3["name"] == i_category and v == "android.intent.category.LAUNCHER":
                    has_launcher = True
            if has_main and has_launcher:
                targets.append((j, rng[j]))
    if not targets:
        raise SystemExit("no MAIN/LAUNCHER intent-filter found on <%s>"
                         % old_activity)
    for start, end in sorted(targets, reverse=True):
        del nodes[start:end + 1]
    print("  removed %d launcher filter(s) from <%s>" % (len(targets), old_activity))

    # 2) insert the new launcher activity right before </application>
    i_app = pool.index("application")
    insert_at = None
    depth = 0
    for idx, (t, node) in enumerate(nodes):
        if t == RES_XML_START_EL:
            depth += 1
        elif t == RES_XML_END_EL:
            depth -= 1
            if depth == 1 and node["name"] == i_app:
                insert_at = idx
                break
    if insert_at is None:
        raise SystemExit("</application> not found")

    i_new = pool.add(new_activity)
    i_exp = pool.add("exported")
    i_orient = pool.add("screenOrientation")
    for (t, node) in nodes:
        if t == RES_XML_START_EL and node["name"] == i_act \
                and _attr_str(pool, ns, node, i_name) == new_activity:
            raise SystemExit("<activity %s> already present" % new_activity)

    new_nodes = [
        (RES_XML_START_EL, {"ns": NO_ENTRY, "name": i_act, "attrs": [
            {"ns": ns, "name": i_name, "type": TYPE_STRING, "data": i_new},
            {"ns": ns, "name": i_exp, "type": TYPE_INT_BOOLEAN, "data": 1},
            {"ns": ns, "name": i_orient, "type": TYPE_INT_DEC, "data": 1},
        ]}),
        (RES_XML_START_EL, {"ns": NO_ENTRY, "name": i_filter, "attrs": []}),
        (RES_XML_START_EL, {"ns": NO_ENTRY, "name": i_action, "attrs": [
            {"ns": ns, "name": i_name, "type": TYPE_STRING, "data": i_main},
        ]}),
        (RES_XML_END_EL, {"ns": NO_ENTRY, "name": i_action}),
        (RES_XML_START_EL, {"ns": NO_ENTRY, "name": i_category, "attrs": [
            {"ns": ns, "name": i_name, "type": TYPE_STRING, "data": i_launcher},
        ]}),
        (RES_XML_END_EL, {"ns": NO_ENTRY, "name": i_category}),
        (RES_XML_END_EL, {"ns": NO_ENTRY, "name": i_filter}),
        (RES_XML_END_EL, {"ns": NO_ENTRY, "name": i_act}),
    ]
    nodes[insert_at:insert_at] = new_nodes
    print("  <activity %s> launcher inserted at chunk %d" % (new_activity, insert_at))
    print("size: %d -> %d" % (len(open(src, "rb").read()), save(dst, pool, resmap, nodes)))


def cmd_add_perm(src, dst, perms):
    """add <uses-permission> entries right after <manifest>'s opening tag"""
    pool, resmap, nodes = load(src)
    ns = android_ns(pool)
    i_name = pool.index("name")
    i_perm = pool.index("uses-permission")
    if i_perm < 0:
        i_perm = pool.add("uses-permission")

    have = set()
    for (t, node) in nodes:
        if t != RES_XML_START_EL or node["name"] != i_perm:
            continue
        for a in node["attrs"]:
            if a["name"] == i_name and a["type"] == TYPE_STRING:
                have.add(pool.strings[a["data"]])

    insert_at = None
    for idx, (t, node) in enumerate(nodes):
        if t == RES_XML_START_EL and pool.strings[node["name"]] == "manifest":
            insert_at = idx + 1
            break
    if insert_at is None:
        raise SystemExit("<manifest> not found")

    added = []
    new_nodes = []
    for p in perms:
        if p in have:
            print("  already present: %s" % p)
            continue
        i_val = pool.add(p)
        attrs = [{"ns": ns, "name": i_name, "type": TYPE_STRING, "data": i_val}]
        new_nodes.append((RES_XML_START_EL, {"ns": NO_ENTRY, "name": i_perm, "attrs": attrs}))
        new_nodes.append((RES_XML_END_EL, {"ns": NO_ENTRY, "name": i_perm}))
        added.append(p)
        print("  added: %s" % p)

    nodes[insert_at:insert_at] = new_nodes
    print("total added: %d" % len(added))
    print("size: %d -> %d" % (len(open(src, "rb").read()), save(dst, pool, resmap, nodes)))


def cmd_dump(src):
    pool, resmap, nodes = load(src)
    depth = 0
    for t, node in nodes:
        if t == RES_XML_START_EL:
            nm = pool.strings[node["name"]]
            print("  " * depth + "<" + nm)
            for a in node["attrs"]:
                an = pool.strings[a["name"]]
                if a["type"] == TYPE_STRING:
                    v = pool.strings[a["data"]]
                    v = '"%s"' % v
                elif a["type"] == TYPE_INT_BOOLEAN:
                    v = "true" if a["data"] else "false"
                else:
                    v = str(a["data"])
                print("  " * (depth + 1) + "android:%s=%s" % (an, v))
            depth += 1
        elif t == RES_XML_END_EL:
            depth -= 1
            print("  " * depth + "</" + pool.strings[node["name"]] + ">")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "add-provider" and len(argv) == 6:
        cmd_add_provider(argv[2], argv[3], argv[4], argv[5])
    elif cmd == "set-launcher" and len(argv) == 6:
        cmd_set_launcher(argv[2], argv[3], argv[4], argv[5])
    elif cmd == "drop-attr" and len(argv) >= 6 and (len(argv) - 4) % 2 == 0:
        pairs = [(argv[i], argv[i + 1]) for i in range(4, len(argv), 2)]
        cmd_drop_attr(argv[2], argv[3], pairs)
    elif cmd == "set-bool" and len(argv) >= 7 and (len(argv) - 4) % 3 == 0:
        triples = [(argv[i], argv[i + 1], argv[i + 2]) for i in range(4, len(argv), 3)]
        cmd_set_bool(argv[2], argv[3], triples)
    elif cmd == "add-perm" and len(argv) >= 4:
        cmd_add_perm(argv[2], argv[3], argv[4:])
    elif cmd == "dump" and len(argv) == 3:
        cmd_dump(argv[2])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
