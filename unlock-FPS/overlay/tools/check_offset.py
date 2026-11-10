r"""
check_offset.py -- 出包前离线确认 targetFrameRate 的偏移还对不对。

不用装 APK、不用启动游戏：直接把 arm64 split 里的 libunity.so 读出来，
按 ELF 程序头把虚拟地址换算成文件偏移，读那个 int32。

    正常值：-1（原厂默认）、0、或 15~480 之间的整数

用法：
    python tools/check_offset.py apk\split_arm64.apk            # 查默认 0x199cc54
    python tools/check_offset.py apk\jp\split_arm64.apk 0x1aabbcc

读出来是别的数（比如一片随机值），说明这个版本的 offset 变了，
新包启动时会在面板上显示「扫描 x.y.z」自己找；真找不到才会显示「回退」。
"""

import struct
import sys
import zipfile


def load_libunity(apk):
    z = zipfile.ZipFile(apk)
    names = [n for n in z.namelist() if n.endswith("libunity.so")]
    if not names:
        raise SystemExit("%s: 里面没有 libunity.so（是不是传了 base.apk？so 在 split 里）" % apk)
    return names[0], z.read(names[0])


def vaddr_to_file(data, vaddr):
    e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)
    for i in range(e_phnum):
        p = e_phoff + i * e_phentsize
        if struct.unpack_from("<I", data, p)[0] != 1:      # PT_LOAD
            continue
        p_offset, p_vaddr = struct.unpack_from("<QQ", data, p + 8)
        p_filesz = struct.unpack_from("<Q", data, p + 32)[0]
        if p_vaddr <= vaddr < p_vaddr + p_filesz:
            return p_offset + (vaddr - p_vaddr)
    return None


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__)
        return 2
    apk = argv[1]
    off = int(argv[2], 0) if len(argv) == 3 else 0x199CC54

    name, data = load_libunity(apk)
    print("%s -> %s (%d bytes)" % (apk, name, len(data)))

    f = vaddr_to_file(data, off)
    if f is None:
        print("vaddr 0x%x 不在任何 PT_LOAD 段里" % off)
        return 1

    v = struct.unpack_from("<i", data, f)[0]
    ok = (v == -1 or v == 0 or 15 <= v <= 480)
    print("vaddr 0x%x -> file 0x%x  value=%d  %s"
          % (off, f, v, "OK" if ok else "!! 可疑，这个版本的偏移可能变了"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
