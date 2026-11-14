#!/usr/bin/env python3
"""Touhou LostWord (GL) 简体中文补丁 v1.5 —— 安装 / 还原 / 校验

一次把两类补丁写进设备：

  1. 资源包补丁   UnityCache/Shared/<containerHash>/<entryHash>/__data
      UI 文本、UI 贴图、字体。
  2. 主表补丁     /data/user/0/<pkg>/files/cache/<bundleHash>
      绘卷名/解说/被动、角色能力、技能、特性等（AES 加密表）。

设计要点
--------
* 不碰 APK、不重打包、不改签名，随时可还原。
* 每条缓存条目写 __info 时必须满足 ``-1\\n<epoch>\\n1\\n__data``，且 epoch 等于
  新 __data 的 mtime；否则 Unity 判定缓存失效会重新下载覆盖补丁。
* 只允许写测试机（默认 emulator-5556），避免误伤生产实例。
* 安装前把原文件备份到设备 /data/local/tmp/tlw-v15-backup/。

用法
----
    python tlw_install.py install  [--serial X] [--dry-run]
    python tlw_install.py restore  [--serial X] [--dry-run]
    python tlw_install.py verify   [--serial X]

依赖：msgpack、cryptography（仅主表校验时需要）
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = "jp.goodsmile.touhoulostwordglobal_android"
DEFAULT_SERIAL = "emulator-5556"
PRODUCTION_SERIALS = {"emulator-5554", "127.0.0.1:5554"}

# Android/data roots, most reliable first. /sdcard is a symlink that can be missing right
# after an emulator boot, and on LDPlayer its FUSE view makes `find` not descend.
DATA_ROOTS = [
    "/data/media/0/Android/data",
    "/storage/emulated/0/Android/data",
    "/sdcard/Android/data",
    "/mnt/user/0/emulated/0/Android/data",
]

BACKUP_DIR = "/data/local/tmp/tlw-v15-backup"
TMP_DIR = "/data/local/tmp"


# ---------------------------------------------------------------- adb helpers

def _adb_bin():
    for cand in (
        os.environ.get("ADB"),
        r"C:\leidian\LDPlayer14\adb.exe",
        shutil.which("adb"),
    ):
        if cand and os.path.exists(cand):
            return cand
    raise SystemExit("找不到 adb。请设置环境变量 ADB 指向 adb.exe")


ADB = None


def adb(*args, serial=None, timeout=180, check=False):
    global ADB
    if ADB is None:
        ADB = _adb_bin()
    cmd = [ADB]
    if serial:
        cmd += ["-s", serial]
    cmd += list(args)
    env = dict(os.environ)
    # Git Bash on Windows rewrites absolute /android paths into C:/Program Files/Git/...
    env["MSYS_NO_PATHCONV"] = "1"
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {p.stderr or p.stdout}")
    return p


def sh(serial, cmd, timeout=180):
    return adb("shell", cmd, serial=serial, timeout=timeout)


def push(serial, local, remote, timeout=600):
    return adb("push", local, remote, serial=serial, timeout=timeout)


# ---------------------------------------------------------------- device probing

def require_device(serial, force=False):
    if serial in PRODUCTION_SERIALS and not force:
        raise SystemExit(
            f"拒绝写入生产实例 {serial}。\n"
            f"这是只读的正式机。换用测试机，或确认无误后加 --force。"
        )
    p = sh(serial, "echo ok", timeout=30)
    if p.returncode != 0 or "ok" not in p.stdout:
        raise SystemExit(f"设备 {serial} 无响应，先启动模拟器再试")


def is_rooted(serial):
    return "uid=0" in sh(serial, "id", timeout=30).stdout


def ensure_root(serial):
    if is_rooted(serial):
        return True
    adb("root", serial=serial, timeout=60)
    import time

    for _ in range(10):
        time.sleep(2)
        if is_rooted(serial):
            return True
    return False


def package_installed(serial):
    out = sh(serial, f"pm list packages {PKG}", timeout=60).stdout
    return PKG in out


def installed_version(serial):
    for cmd in (
        f"dumpsys package {PKG} | grep -m1 versionName",
        f"pm dump {PKG} | grep -m1 versionName",
    ):
        for line in sh(serial, cmd, timeout=60).stdout.splitlines():
            if "versionName=" in line:
                return line.split("versionName=", 1)[1].strip()
    return ""


def find_data_root(serial):
    """Return the Android/data root that actually holds UnityCache entries."""
    existing = None
    for root in DATA_ROOTS:
        probe = f"{root}/{PKG}/files/UnityCache/Shared"
        out = sh(serial, f"find {probe} -name __data 2>/dev/null | wc -l", timeout=300)
        txt = out.stdout.strip().splitlines()
        n = 0
        if txt:
            try:
                n = int(txt[-1].strip())
            except ValueError:
                n = 0
        if n > 0:
            return root
        if existing is None:
            chk = sh(serial, f"[ -d {root}/{PKG} ] && echo yes || echo no", timeout=30)
            if "yes" in chk.stdout:
                existing = root
    return existing


def cache_dir(serial):
    return f"/data/user/0/{PKG}/files/cache"


def app_owner(serial):
    """Read the app data dir's real owner instead of assuming u0_a74.

    The UID depends on install order, so a hardcoded value silently leaves the
    patched master tables owned by the wrong user and the game cannot read them.
    """
    out = sh(serial, f"stat -c '%U:%G' /data/user/0/{PKG}", timeout=30).stdout.strip()
    if ":" in out and "u0_" in out:
        return out
    raise SystemExit(f"无法确定游戏 UID（stat 返回 {out!r}）")


# ---------------------------------------------------------------- payload loading

def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def file_md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def bundles():
    """[(device_rel, local_file)] for UnityCache payload."""
    man = load_json(os.path.join(HERE, "payload", "bundles.json"))
    out = []
    for r in man:
        local = os.path.join(HERE, "payload", r["file"])
        if os.path.exists(local):
            out.append((r["device_rel"], local))
    return out


def masters():
    """[(bundle_hash, local_file)] for masterdata payload."""
    man = load_json(os.path.join(HERE, "payload", "masters.json"))
    out = []
    for r in man:
        local = os.path.join(HERE, "payload", r["file"])
        if os.path.exists(local):
            out.append((r["hash"], local))
    return out


def stories():
    """[(device_rel, local_file)] for story payload.

    Story bundles can be pre-seeded even when the game has never downloaded them: the
    UnityCache is a plain directory tree with no global index, so creating
    Shared/<container>/<entry>/{__data,__info} is enough for the runtime to adopt them.
    """
    path = os.path.join(HERE, "payload", "story.json")
    if not os.path.exists(path):
        return []
    out = []
    for r in load_json(path):
        local = os.path.join(HERE, "payload", r["file"])
        if os.path.exists(local):
            out.append((r["device_rel"], local))
    return out


# ---------------------------------------------------------------- install

def write_info(serial, entry_dir):
    return sh(
        serial,
        f"E=$(stat -c %Y {entry_dir}/__data) && "
        f"printf -- '-1\\n%s\\n1\\n__data\\n' $E > {entry_dir}/__info && "
        f"touch -d @$E {entry_dir}/__info && echo epoch=$E",
        timeout=60,
    )


def install_bundles(serial, root, dry=False):
    items = bundles()
    print(f"\n[1/3] 资源包：{len(items)} 个")
    present_counts = sh(
        serial,
        f"find {root}/{PKG}/files/UnityCache/Shared -name __data 2>/dev/null | wc -l",
        timeout=300,
    ).stdout.strip().splitlines()
    have = present_counts[-1].strip() if present_counts else "0"
    print(f"      设备现有缓存条目：{have}")

    uc = f"{root}/{PKG}/files/UnityCache"
    ok = skipped = fail = 0
    fail_list = []
    for i, (rel, local) in enumerate(items, 1):
        dev_data = f"{uc}/{rel}"
        dev_dir = dev_data[:-len("/__data")] if dev_data.endswith("/__data") else dev_data
        if dry:
            ok += 1
            continue
        exists = sh(serial, f"[ -f {dev_data} ] && echo yes || echo no", timeout=30)
        if "yes" not in exists.stdout:
            skipped += 1
            continue

        tag = rel.replace("/", "_").replace("__data", "").rstrip("_")[:70]
        sh(serial, f"mkdir -p {BACKUP_DIR}", timeout=60)
        sh(serial, f"cp -a {dev_data} {BACKUP_DIR}/{tag}.data.bak", timeout=120)
        sh(serial, f"cp -a {dev_dir}/__info {BACKUP_DIR}/{tag}.info.bak", timeout=60)

        remote = f"{TMP_DIR}/{tag}.b"
        p = push(serial, local, remote)
        if p.returncode != 0:
            fail += 1
            fail_list.append((rel, "push failed"))
            continue
        sh(serial, f"cp {remote} {dev_data}", timeout=120)
        write_info(serial, dev_dir)
        got = sh(serial, f"md5sum {dev_data}", timeout=60).stdout.split()
        want = file_md5(local)
        if got and got[0] == want:
            ok += 1
        else:
            fail += 1
            fail_list.append((rel, "md5 mismatch"))
        if i % 40 == 0:
            print(f"      {i}/{len(items)} ok={ok} skip={skipped} fail={fail}", flush=True)

    print(f"      完成：写入 {ok}，跳过(设备无此缓存) {skipped}，失败 {fail}")
    for rel, why in fail_list[:10]:
        print(f"        失败 {rel} :: {why}")
    return ok, skipped, fail


def install_stories(serial, root, dry=False):
    """Pre-seed story bundles, creating the cache entry when the game has not fetched it."""
    items = stories()
    if not items:
        print("\n[3/3] 剧情：跳过（payload 未包含）")
        return 0, 0, 0
    print(f"\n[3/3] 剧情：{len(items)} 个")
    uc = f"{root}/{PKG}/files/UnityCache"
    ok = skip = fail = 0
    fail_list = []
    for i, (rel, local) in enumerate(items, 1):
        dev_data = f"{uc}/{rel}"
        dev_dir = dev_data[:-len("/__data")] if dev_data.endswith("/__data") else dev_data
        if dry:
            ok += 1
            continue
        tag = rel.replace("/", "_").replace("__data", "").rstrip("_")[:70]
        # A story entry that already exists is someone else's data (possibly the game's
        # own download); back it up. A missing one is normal on a fresh account, so we
        # create the pair of files instead of skipping.
        exists = sh(serial, f"[ -f {dev_data} ] && echo yes || echo no", timeout=30)
        if "yes" in exists.stdout:
            sh(serial, f"mkdir -p {BACKUP_DIR}", timeout=60)
            sh(serial, f"cp -a {dev_data} {BACKUP_DIR}/{tag}.data.bak", timeout=120)
            sh(serial, f"cp -a {dev_dir}/__info {BACKUP_DIR}/{tag}.info.bak", timeout=60)
        else:
            mk = sh(serial, f"mkdir -p {dev_dir}", timeout=60)
            if mk.returncode != 0:
                fail += 1
                fail_list.append((rel, "mkdir failed: " + (mk.stderr or mk.stdout)[:60]))
                continue

        remote = f"{TMP_DIR}/{tag}.story"
        p = push(serial, local, remote)
        if p.returncode != 0:
            fail += 1
            fail_list.append((rel, "push failed"))
            continue
        sh(serial, f"cp {remote} {dev_data}", timeout=120)
        write_info(serial, dev_dir)
        got = sh(serial, f"md5sum {dev_data}", timeout=60).stdout.split()
        if got and got[0] == file_md5(local):
            ok += 1
        else:
            fail += 1
            fail_list.append((rel, "md5 mismatch"))
        if i % 40 == 0:
            print(f"      {i}/{len(items)} ok={ok} fail={fail}", flush=True)

    print(f"      完成：写入 {ok}，失败 {fail}")
    for rel, why in fail_list[:10]:
        print(f"        失败 {rel} :: {why}")
    return ok, skip, fail


def install_masters(serial, dry=False):
    items = masters()
    cdir = cache_dir(serial)
    print(f"\n[2/3] 主表：{len(items)} 张")
    ok = skip = fail = 0
    fail_list = []
    owner = app_owner(serial)
    print(f"      游戏文件属主：{owner}")
    sh(serial, f"mkdir -p {BACKUP_DIR}", timeout=60)
    for i, (h, local) in enumerate(items, 1):
        dev = f"{cdir}/{h}"
        if dry:
            ok += 1
            continue
        exists = sh(serial, f"su -c '[ -f {dev} ] && echo yes || echo no'", timeout=30)
        if "yes" not in exists.stdout:
            skip += 1
            continue
        # backup + replace + fix ownership/permissions
        remote = f"{TMP_DIR}/{h}.master"
        p = push(serial, local, remote)
        if p.returncode != 0:
            fail += 1
            fail_list.append((h, "push failed"))
            continue
        cmd = (
            f"cp -f {dev} {BACKUP_DIR}/{h}.bak; "
            f"cp -f {remote} {dev} && "
            f"chown {owner} {dev} && chmod 600 {dev} && echo ok"
        )
        r = sh(serial, f"su -c \"{cmd}\"", timeout=120)
        if "ok" in r.stdout:
            got = sh(serial, f"su -c 'md5sum {dev}'", timeout=60).stdout.split()
            if got and got[0] == file_md5(local):
                ok += 1
            else:
                fail += 1
                fail_list.append((h, "md5 mismatch"))
        else:
            fail += 1
            fail_list.append((h, (r.stderr or r.stdout)[:60]))
        if i % 20 == 0:
            print(f"      {i}/{len(items)} ok={ok} skip={skip} fail={fail}", flush=True)

    print(f"      完成：写入 {ok}，跳过(设备无此表) {skip}，失败 {fail}")
    for h, why in fail_list[:10]:
        print(f"        失败 {h} :: {why}")
    return ok, skip, fail


def cmd_install(args):
    require_device(args.serial, args.force)
    if not package_installed(args.serial):
        raise SystemExit("游戏未安装。先装好游戏并启动一次（让它生成缓存），再来打补丁。")
    ver = installed_version(args.serial)
    print(f"设备      : {args.serial}")
    print(f"游戏版本  : {ver or '未知'}")
    expect = load_json(os.path.join(HERE, "payload", "meta.json")).get("game_version")
    if ver and expect and ver != expect:
        print(f"警告      : 补丁基于 {expect} 制作，设备是 {ver}，可能不完全匹配")

    if not args.dry_run and not ensure_root(args.serial):
        raise SystemExit("需要 root 才能写入游戏私有目录（adb root 失败）")

    root = find_data_root(args.serial)
    if root is None and not args.dry_run:
        raise SystemExit("找不到游戏的 Android/data 目录。先启动游戏一次再试。")
    if args.dry_run:
        print("\n[dry-run] 只检查，不写入")
        b = bundles()
        m = masters()
        s = stories()
        print(f"      资源包 {len(b)} 个，主表 {len(m)} 张，剧情 {len(s)} 个")
        return 0

    print(f"缓存根    : {root}")
    ok1, skip1, fail1 = install_bundles(args.serial, root, dry=False)
    ok2, skip2, fail2 = install_masters(args.serial, dry=False)
    ok3, skip3, fail3 = install_stories(args.serial, root, dry=False)

    print("\n" + "=" * 52)
    print(f"资源包 写入 {ok1} / 跳过 {skip1} / 失败 {fail1}")
    print(f"主表   写入 {ok2} / 跳过 {skip2} / 失败 {fail2}")
    print(f"剧情   写入 {ok3} / 跳过 {skip3} / 失败 {fail3}")
    if fail1 + fail2 + fail3 == 0:
        print("\n安装完成。重启游戏即可看到中文。")
        print("如果某处仍是英文：进游戏让该界面加载一次资源，再重跑本脚本。")
        return 0
    print("\n有失败项，见上面的清单。")
    return 1


def cmd_restore(args):
    require_device(args.serial, args.force)
    if not ensure_root(args.serial):
        raise SystemExit("需要 root")
    root = find_data_root(args.serial)
    print(f"从 {BACKUP_DIR} 还原")

    # bundles
    items = bundles()
    ok = miss = 0
    for rel, _local in items:
        tag = rel.replace("/", "_").replace("__data", "").rstrip("_")[:70]
        dev_data = f"{root}/{PKG}/files/UnityCache/{rel}"
        dev_dir = dev_data[:-len("/__data")] if dev_data.endswith("/__data") else dev_data
        chk = sh(serial=args.serial, cmd=f"[ -f {BACKUP_DIR}/{tag}.data.bak ] && echo yes || echo no", timeout=30)
        if "yes" not in chk.stdout:
            miss += 1
            continue
        if args.dry_run:
            ok += 1
            continue
        sh(args.serial, f"cp -f {BACKUP_DIR}/{tag}.data.bak {dev_data}", timeout=120)
        write_info(args.serial, dev_dir)
        ok += 1
    print(f"资源包还原 {ok}，无备份 {miss}")

    # masters
    cdir = cache_dir(args.serial)
    owner = app_owner(args.serial)
    ok2 = miss2 = 0
    for h, _local in masters():
        chk = sh(args.serial, f"su -c '[ -f {BACKUP_DIR}/{h}.bak ] && echo yes || echo no'", timeout=30)
        if "yes" not in chk.stdout:
            miss2 += 1
            continue
        if args.dry_run:
            ok2 += 1
            continue
        cmd = (
            f"cp -f {BACKUP_DIR}/{h}.bak {cdir}/{h} && "
            f"chown {owner} {cdir}/{h} && chmod 600 {cdir}/{h} && echo ok"
        )
        sh(args.serial, f"su -c \"{cmd}\"", timeout=120)
        ok2 += 1
    print(f"主表还原 {ok2}，无备份 {miss2}")

    # story: entries we created had no original, so restore means deleting them
    ok3 = removed = miss3 = 0
    for rel, _local in stories():
        tag = rel.replace("/", "_").replace("__data", "").rstrip("_")[:70]
        dev_data = f"{root}/{PKG}/files/UnityCache/{rel}"
        dev_dir = dev_data[:-len("/__data")] if dev_data.endswith("/__data") else dev_data
        chk = sh(args.serial, cmd=f"[ -f {BACKUP_DIR}/{tag}.data.bak ] && echo yes || echo no", timeout=30)
        if "yes" in chk.stdout:
            if args.dry_run:
                ok3 += 1
                continue
            sh(args.serial, f"cp -f {BACKUP_DIR}/{tag}.data.bak {dev_data}", timeout=120)
            write_info(args.serial, dev_dir)
            ok3 += 1
        elif args.dry_run:
            removed += 1
        else:
            # we pre-seeded it; removing the directory returns the cache to "not fetched"
            sh(args.serial, f"rm -rf {dev_dir}", timeout=60)
            removed += 1
    print(f"剧情还原 {ok3}，删除预置 {removed}，无备份 {miss3}")
    print("\n还原完成。重启游戏生效。")
    return 0


def cmd_verify(args):
    require_device(args.serial, args.force)
    root = find_data_root(args.serial)
    if root is None:
        print("找不到缓存目录"); return 1
    uc = f"{root}/{PKG}/files/UnityCache"
    bad = 0
    print("资源包校验：")
    ok = absent = 0
    for rel, local in bundles():
        dev_data = f"{uc}/{rel}"
        dev_dir = dev_data[:-len("/__data")] if dev_data.endswith("/__data") else dev_data
        out = sh(args.serial, f"md5sum {dev_data} 2>/dev/null", timeout=60).stdout.split()
        if not out:
            absent += 1
            continue
        want = file_md5(local)
        if out[0] == want:
            ok += 1
        else:
            bad += 1
            print(f"  不一致 {rel}")
    print(f"  一致 {ok}  不一致 {bad}  未缓存 {absent}")

    print("主表校验：")
    cdir = cache_dir(args.serial)
    ok2 = bad2 = absent2 = 0
    for h, local in masters():
        out = sh(args.serial, f"su -c 'md5sum {cdir}/{h}' 2>/dev/null", timeout=60).stdout.split()
        if not out or len(out[0]) != 32:
            absent2 += 1
            continue
        if out[0] == file_md5(local):
            ok2 += 1
        else:
            bad2 += 1
            print(f"  不一致 {h}")
    print(f"  一致 {ok2}  不一致 {bad2}  不存在 {absent2}")

    print("剧情校验：")
    ok3 = bad3 = absent3 = 0
    for rel, local in stories():
        dev_data = f"{uc}/{rel}"
        out = sh(args.serial, f"md5sum {dev_data} 2>/dev/null", timeout=60).stdout.split()
        if not out:
            absent3 += 1
            continue
        if out[0] == file_md5(local):
            ok3 += 1
        else:
            bad3 += 1
            print(f"  不一致 {rel}")
    print(f"  一致 {ok3}  不一致 {bad3}  不存在 {absent3}")
    return 0 if bad + bad2 + bad3 == 0 else 1


def main():
    ap = argparse.ArgumentParser(description="Touhou LostWord GL 简体中文补丁 v1.5")
    ap.add_argument("command", choices=["install", "restore", "verify"])
    ap.add_argument("--serial", default=DEFAULT_SERIAL)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="允许对非默认设备操作")
    args = ap.parse_args()

    if args.command == "install":
        return cmd_install(args)
    if args.command == "restore":
        return cmd_restore(args)
    return cmd_verify(args)


if __name__ == "__main__":
    sys.exit(main() or 0)
