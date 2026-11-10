# CN 汉化数据安装规范（LwLocal v1.3 / 内置安装器必须遵守）

> 版本：2026-11-09（cn-analyst / task-1）
> 适用：`xiake595/lostword-cn-patch` v1.3 数据包 `lwlocal.zip`（445,336,186 B，SHA-256 `a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792`）
> 目标：把汉化数据内置进重打包 APK（`jp.goodsmile.touhoulostwordglobal_android` 1.57.0 / 6728），首次启动时解包落盘，让游戏读到汉化资源。
> 配套台账：`integrated/docs/cn_data_inventory.json`（计数/字节/sha256 样本/version/映射，机器可读）。

---

## 0. 结论摘要（先看这里）

| 问题 | 结论 | 证据等级 |
|---|---|---|
| 官方 v1.3 的安装机制 | 唯一 hook 是 `Application.attach` 后起后台线程写文件，**没有任何资源加载/下载/缓存 hook** | **已反编译确证**（jadx 全文 462 行，见 §2） |
| 写 `__data` 是否要同时写 `__info` | **不要写**。官方全程只写 `__data`，zip 里也没有 `__info`；写错格式的 `__info` 可能反而有害 | 已确证（官方代码/数据包） |
| 「首启前把 345 个 `__data` 预置到 UnityCache，设备原本无缓存」是否可行 | **可行（推断，高置信）**：游戏判定"已缓存"完全基于磁盘缓存；预置就是喂给 Unity 缓存层。游戏不会主动去删/重下"它认为已缓存"的条目 | **推断 + 间接证据**（§5；Unity 6 原生 `IsVersionCached` 未 100% 反证） |
| `master` 是 84 还是 83 张表 | zip 里 84 个文件 = **83 张 hash 表 + `manifest.json`**；官方模块把 84 项全部写进 `files/cache/`（多写 `manifest.json` 无害）。repo `manifest.json` 的 `master_tables` 84 条也把 `manifest.json` 算了一条 | 已确证（文件级统计） |
| zip 里 5 个不在 repo manifest 里的 bundle | v1.1 新增的 5 个**场景包**（活动/登录奖励/扫荡/能力封印/肉鸽选人），**必须安装** | 已确证（UnityFS 头解析出资源名） |
| `version.txt` 该用哪个 | zip 内 `lwlocal/version.txt` 是**滞后的 `v1.1-20261108`**；真实版本是 Release 独立资产 `version.txt` = **`v1.3-20261109b`**。官方模块只跳过该条目、不读内容 | 已确证（逐字节比对） |

---

## 1. 数据来源与版本

| 项 | 值 |
|---|---|
| Release | `v1.3`（`剧情台词 + 技能名汉化`，2026-11-09） |
| 数据包 | `lwlocal.zip`，445,336,186 B，**430 entries，全部 STORED（压缩方式 0，无 extra 字段）** |
| zip SHA-256 | `a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792`（与作者 README 声明一致，已实测） |
| Release 独立 `version.txt` | `v1.3-20261109b`（14 B，无换行） |
| zip 内 `lwlocal/version.txt` | `v1.1-20261108\n`（**滞后元数据**，官方模块 unzip 时显式跳过所有 `version.txt`） |
| 模块 | `LwLocal-1.3.apk`（16 KB，`package lw.mod`，Xposed/LSPatch 模块，`assets/xposed_init` = `lw.mod.LwLocalHook`，classes.dex 10,636 B） |
| 游戏 | global 1.57.0 / versionCode 6728；Unity **6000.0.58f2**（Unity 6），IL2CPP，Stripping Disabled |

---

## 2. 官方机制：LwLocal v1.3 到底做了什么

反编译产物：`work/cn-analysis/jadx-out/sources/lw/mod/LwLocalHook.java`（jadx 1.5.6，唯一源文件）。

### 2.1 Hook 点与时机

- 类：`lw.mod.LwLocalHook implements IXposedHookLoadPackage, IXposedHookZygoteInit`
- 常量：`TARGET=jp.goodsmile.touhoulostwordglobal_android`、`TAG=LwLocal`、`DATA_VER=v1-20261108`、`MARKER=lwlocal.ver`、`ZIP_NAME=lwlocal_dl.zip`
- **唯一 hook**：`XposedBridge.hookAllMethods(android.app.Application.class, "attach", ...)`，`afterHookedMethod` 里：
  1. 用 `synchronized + static boolean started` 保证进程内只跑一次；
  2. `new Thread(..., TAG).start()` → 后台线程执行 `boot(Application)`。
- **没有任何** hook 资源加载、AssetBundle 下载、`Caching`、`File`、`UnityWebRequest`，也没有改动游戏 manifest/Activity。模块完全在"游戏启动早期往磁盘写文件"，之后依赖游戏自己的缓存逻辑命中。
- 与我们的内置安装器的关系：官方模块是在 `Application.attach` 之后**与游戏启动并发**写文件（存在竞态，靠作者反复迭代规避）；我们的 `CnSetupActivity` 在**启动 Unity 游戏 Activity 之前**完成解包，时序严格更早、无竞态。

### 2.2 boot() 伪代码（关键逻辑，逐行对应反编译）

```java
void boot(Context ctx) {
    File filesDir = ctx.getFilesDir();                 // /data/data/<pkg>/files
    String marker = readMarker(filesDir);              // filesDir/lwlocal.ver（trim）
    String baseUrl = null, version = DATA_VER;         // "v1-20261108" 离线回退值
    for (String u : BASE_URLS) {                       // 4 个源逐个试
        try {
            version = fetchText(u + "version.txt").trim();   // 10s connect / 10s read
            if (version.length() > 0) { baseUrl = u; break; }
        } catch (Throwable t) { /* 试下一个源 */ }
    }
    // 幂等判定：版本一致 且 filesDir/cache 文件数 > 50 → 直接 return
    if (version.equals(marker) && countFiles(new File(filesDir, "cache")) > 50) {
        xlog("up-to-date " + version); return;
    }
    if (baseUrl == null) { xlog("no reachable source, skip"); return; } // 无网=不装，下次启动再试

    File zip = new File(filesDir, "lwlocal_dl.zip");   // 本地预置包（>=1MB 可直接用）
    if (zip.isFile() && zip.length() >= 1_000_000) {
        try { int[] n = unzip(zip, ctx); writeMarker(filesDir, version); zip.delete(); return; }
        catch (Throwable t) { zip.delete(); }          // 本地包坏了就继续在线下载
    }
    for (String u : BASE_URLS) {                       // 在线下载，逐源回退
        try {
            download(u + "lwlocal.zip", zip);          // 128KB buffer；校验 Content-Length
            int[] n = unzip(zip, ctx);
            writeMarker(filesDir, version);            // marker 内容 = 远端 version.txt 文本
            zip.delete(); return;
        } catch (Throwable t) { zip.delete(); }        // "source failed"，换下一个源
    }
    xlog("all sources failed, will retry next launch"); // 单次启动不重试，失败等下个进程
}
```

要点：
- **源回退顺序**：`https://github.com/.../releases/latest/download/` → `https://gh-proxy.com/https://github.com/...` → `https://ghproxy.net/https://github.com/...` → `http://127.0.0.1:8899/`。
- **无校验**：下载只比对 `Content-Length`，**不校验 SHA-256/CRC**（README 声明的 sha256 仅给人手动核对）。
- **失败语义**：单个源失败删半成品换下一个；全部失败只打日志，**下次启动重试**（无同日重试、无退避）。
- **本地包路径是 `getFilesDir()/lwlocal_dl.zip`（内部私有目录）**，不是 README v1.1 说的外部 `Android/data/<pkg>/files/lwlocal.zip`（旧文档与代码不符）。

### 2.3 unzip() / write()：写入目标与覆盖语义

```java
int[] unzip(File zip, Context ctx) {
    File cache = new File(ctx.getFilesDir(), "cache");            // 内部私有
    makeDirs(cache);
    File unityShared = new File(ctx.getExternalFilesDir(null), "UnityCache/Shared");
    makeDirs(unityShared);
    ZipInputStream zis = new ZipInputStream(new FileInputStream(zip));
    for (entry = zis.getNextEntry(); entry != null; entry = zis.getNextEntry()) {
        String n = entry.getName();
        if (entry.isDirectory() || n.endsWith("version.txt")) continue;   // ① 跳过 version.txt
        if (n.startsWith("lwlocal/master/")) {
            String rel = n.substring(15);
            if (!rel.contains("/")) write(zis, new File(cache, rel));     // ② 平铺写入 cache/
        } else if (n.startsWith("lwlocal/bundles/")) {
            String[] p = n.substring(16).split("/");
            if (p.length == 3 && "__data".equals(p[2])) {
                File dir = new File(new File(unityShared, p[0]), p[1]);
                makeDirs(dir);
                write(zis, new File(dir, "__data"));                     // ③ 写 <A>/<B>/__data
            }
        }
    }
}
boolean write(InputStream in, File dst) {   // 单文件原子覆盖
    File tmp = new File(dst.getParentFile(), dst.getName() + ".tmp");
    copy(in, tmp); tmp.close();
    if (dst.exists() && !dst.delete()) { tmp.delete(); return false; }
    if (tmp.renameTo(dst)) return true;
    tmp.delete(); return false;
}
```

写文件语义（安装器要遵守的硬约束）：
1. **只写 `__data`，绝不写 `__info`**；`__info` 由游戏/Unity 需要时自己生成（官方数据包与新装设备都没有它）。
2. **覆盖 = 先 `delete` 旧文件再 `rename` tmp**：可重复执行、幂等；**不删任何"不在本次 zip 里"的旧文件**（不做清理）。
3. 中间 `.tmp` 文件在失败/进程被杀时可能残留（本文件系统内同目录 rename，无跨分区问题）；不影响游戏，可选在安装开始时清理目标目录下 `*.tmp`。
4. 写入目标都在 **本应用 uid** 下：内部 `getFilesDir()`、外部 `getExternalFilesDir(null)` —— 与游戏同包名同 uid，**不需要 root/权限/chown**（区别于 v1.0 root 版要 `chown` 内部 cache）。
5. 不要修改游戏自己的其他缓存/文件；`files/cache/` 里可能有游戏已有文件，按名覆盖即可。

### 2.4 version.txt / manifest.json 的用途（容易误解，必须写清楚）

| 文件 | 官方模块怎么用 | 我们的安装器 |
|---|---|---|
| `lwlocal/version.txt`（zip 内，v1.1-20261108 滞后） | **不用**：`unzip` 里 `name.endsWith("version.txt")` 直接跳过 | 同样跳过；**不要**把它当版本号 |
| Release 独立 `version.txt`（v1.3-20261109b） | 只用于"远端版本号"：先 fetch 它作为 `version` 字符串，成功后写入 marker | 无网络；把期望版本**硬编码/编译期常量**（建议 `v1.3-20261109b`）写 marker |
| `lwlocal/master/manifest.json`（数据清单，81 条 `{table,file,applied,missing,size}`） | 不读；只因为它在 `master/` 下、名字无 `/`，所以被**当成普通文件写进 `files/cache/manifest.json`** | 与官方一致：写进 cache（84 项之一），但不解析、不用于过滤/校验 |
| repo 根 `manifest.json`（`manifest.json`，340 bundles + 84 master_tables） | 不读（模块 zip 里没有这个文件） | 不解析；只做人工/构建期台账 |
| `lwlocal.ver`（marker） | `readMarker/writeMarker`：内容 = 远端 version.txt 文本（trim），无换行、无其它字段；判定=`版本相等 && filesDir/cache 文件数>50` | 见 §7：建议自有 marker（`files/tlw_cn/installed.txt`），**不要复用游戏目录名** |

> 结论：**官方模块完全不校验 zip 内部数据清单**，装的就是 zip 里全部 430 entries（跳过 version.txt 后 429 个文件）。任何"只装 manifest 列出的文件"的实现都会漏数据（尤其那 5 个额外场景包）。

---

## 3. 安装映射表（精确，内置安装器按此实现）

| zip 内条目 | 落盘目标 | 数量 | 备注 |
|---|---|---|---|
| `lwlocal/bundles/<A>/<B>/__data` | `context.getExternalFilesDir(null)/UnityCache/Shared/<A>/<B>/__data` | **345** | `<A>`、`<B>` 均为 32 位小写 hex，保持原名；只建 `<A>/<B>` 两级目录 |
| `lwlocal/master/<file>` | `context.getFilesDir()/cache/<file>` | **84** | 83 个 32hex 表 + `manifest.json`；平铺，不建子目录 |
| `lwlocal/version.txt` | **跳过**（不落盘） | 1 | 官方模块同样跳过 |
| （无） | `files/cache/manifest.json` 属于上面的 84 项之一 | — | 游戏不读它，多写无害 |
| （无 `__info`） | 不创建 | 0 | **不要臆造** `__info` |

- 总数：**430 entries → 429 个落盘文件** = 345 `__data` + 84 `files/cache` 文件。
- 字节：全部未压缩数据合计 **445,234,868 B**（`bundles` 395,024,307 + `master` 50,210,547 + version.txt 14）；zip 文件 445,336,186 B（差值为 ZIP 头/中央目录）。
- 外部存储路径实际形态：`/storage/emulated/0/Android/data/jp.goodsmile.touhoulostwordglobal_android/files/UnityCache/Shared/<A>/<B>/__data`；内部：`/data/data/jp.goodsmile.touhoulostwordglobal_android/files/cache/<file>`。
- 目录/文件名大小写敏感，`A`、`B` 不要改写、不要 decode/encode。

---

## 4. 数据台账细节（计数/哈希/边界）

机器可读版见 `cn_data_inventory.json`，这里列关键口径：

### 4.1 计数

| 项 | 值 |
|---|---|
| zip entries | 430（全 STORED） |
| bundle `__data` | 345（345 个不同 `<A>` 目录，每目录恰 1 个 `<B>/__data`） |
| `master/` 文件 | 84 = 83 表 + `manifest.json` |
| 落盘文件合计 | 429 |
| repo `manifest.json` bundles | 340（= 345 − 5 个额外场景包） |
| repo `manifest.json` master_tables | 84 条（其中 1 条是 `manifest.json` 文件名） |
| zip 内 `master/manifest.json` 条目 | 81 条 `{table,file,applied,missing,size}` |

### 4.2 三个"清单"口径不一致（这是数据包本身的历史遗留，不要踩坑）

1. **392 表中 2 个表不在 zip 内清单**：`4c6c82a379efc3a6900021cb359ab194`、`6d7c73da9f77e827b76d4bf384bb509b` 在 zip 里但不在 `master/manifest.json`（后者是 v1.1 生成、未随 v1.3 更新）→ **不要用 zip 内 manifest 过滤文件**。
2. **13 个 master 文件大小与 zip 内 manifest 的 `size` 字段不一致**（翻译后 JSON 长度变化；例：`902f9aa853b68bfeee4fa42dfd75a8a2` zip 1,158,960 vs 清单 1,170,464）→ **不要用该 size 做完整性校验**，否则误报。
3. **repo manifest 与 zip 差 5 个 bundle 目录**（见 §4.3）→ 不要用 repo manifest 过滤。

### 4.3 5 个额外 bundle（必须安装）

不在 repo `manifest.json` 的 `bundles` 里、但 v1.1 起就在数据包中（官方模块从不筛选，全部安装）：

| `<A>` | `<B>` | 大小 (B) | UnityFS 内资源名（解析自 bundle 头） |
|---|---|---|---|
| `4412382594c4e8276deee3609268f0c4` | `6f06c2486fef16b82f1211e334502384` | 2,638,407 | `BuildPlayer-EventLoginBonusScene` |
| `7113598fee1ac4c04f47c5ce4a8d4e82` | `7e3343c212f5fa2d0ac02638ad8e79a3` | 2,784,696 | `BuildPlayer-EventScene` |
| `87734df2e56ee8647aa3b9f35821ca50` | `dfc04df13e8660166b3b8ab57700c893` | 593,480 | `BuildPlayer-IdleSearchScene` |
| `b90bfea5da70e7453beabeabe1bf58f3` | `55c7a9787fb3bbd6a55e83ab157195a3` | 1,029,397 | `BuildPlayer-AbilitySealScene` |
| `f4ec32aa29cb5b7897385b52d886201d` | `070880c4dcab0d9beb080a5cd9dc77e0` | 1,103,870 | `BuildPlayer-RogueLitePickUnitScene` |

解读：都是**场景级 UI bundle**（活动、登录奖励、扫荡搜索、能力封印、肉鸽选人界面），对应 v1.1 的"排序/筛选等界面整页汉化 + 字体还原"新增覆盖。manifest 停留在 v1.0 未更新，所以缺 5 条。**漏装它们 → 这 5 个界面仍是日文/英文**。

### 4.4 抽样 sha256（模拟器/真机核对用；另有 6 条在 JSON 内）

```
master/077aacf7784f4f7354e7f716e3ec0bcf        18,400 B    d6e7b0095444469600432dc133959490d7af7015caf403cf9582d3cd365a3c7e
master/07ab80f401847938776e595b87839ebb     2,921,120 B    8465a4309ecdf2ec4725aebbc15d10db52c7be10bc8a5c7cc5cab994729eeeb8
master/08509b44105c08fa1240bcc44ceb1956           416 B    251d3ac7564de997bf759cc6cc72248b5a905ef37a70d39bade1a2a21050ecf6
bundles/006662e3887bc5d201623e96f723449b/b8fe0414e768623f57dbdc064105b65e/__data    984,647 B  ce13eb5af787ac3e6838e41aa6df6f15eb1833d01e0cf55d4f2f4a4c2b33799d
bundles/01686d613089f057172ba7f69b0c0609/0740c12fb68652007dd5bb126c791ff6/__data     22,995 B  3e93bd14c26a25a0e340d46047a1e6f42420b5aa2e4d8f0388b91b609044c630
bundles/034be7d1be2edb47d55148871e0f9882/36f497f26c0b58a9f6a5c773621ab839/__data  1,433,232 B  070a89fc2a17979e1b7db32783e616a9af731bc0b6a38938ee58b7c53d22a469
```

### 4.5 版本字符串

| 来源 | 原文 | 用途 |
|---|---|---|
| Release 独立 `version.txt` | `v1.3-20261109b` | **推荐作为安装器 marker 版本常量** |
| zip 内 `lwlocal/version.txt` | `v1.1-20261108\n`（hex `76312e312d32303236313130380a`） | 落后，仅说明"包内元数据未更新"；不落盘 |
| 模块常量 `DATA_VER` | `v1-20261108` | 仅在 4 个下载源全不可达时作为本地 fallback（不触发安装） |

---

## 5. 关键风险点：首启预置 `__data` 能否让游戏"命中"

### 5.1 问题

设备全新安装、从未启动过游戏 → `UnityCache/Shared` 为空。我们在启动游戏 Activity **之前**写好 345 个 `<A>/<B>/__data`（无 `__info`）。游戏的资源更新检查会不会：
- (A) 认为已缓存 → 跳过下载、直接加载 → ✅ 汉化生效；
- (B) 认为未缓存 → 重新下载原版覆盖我们的 `__data` → ❌ 汉化丢失（不闪退，但白装）。

### 5.2 证据（游戏侧反汇编，非猜测）

对 `base.apk` 的 IL2CPP 二进制做 Il2CppDumper（Unity 6 / metadata v31）+ capstone 反汇编（产物在 `work/cn-analysis/il2cpp-out`、脚本 `disasm_funcs.py`）：

`AssetDownloader.IsCacheValid(AssetLoaderManifest manifest, AssetLoaderManifestAssetInfo info)` 实际逻辑等价于：

```csharp
// RVA 0x1DFAD5C
if (manifest == null || info == null) return false;
if (info.IsAssetBundle) {                       // get_IsAssetBundle @0x1EC7C90
    var h = Hash128.Parse(info.Hash);           // info.Hash 字段 @0x20
    if (!h.isValid) return false;
    return Caching.IsVersionCached(info.Name, h);   // ← Unity 缓存命中判定
} else {
    if (!File.Exists(info.TempPath)) return false;  // 主数据表：只看文件在不在
    return manifest.IsSameHash(info.Name);          // 且清单 hash 与本地一致
}
```

下载/加载侧（`AssetDownloader.AssetBundleRequest` @0x1DF3598）：

```csharp
Uri uri = new Uri(url);
var um = AssetLoader.This().manifest.GetAssetInfo(assetBundleName);
if (um == null) uwr = UnityWebRequestAssetBundle.GetAssetBundle(uri);              // 退化路径
else if (string.IsNullOrEmpty(um.Hash))
    uwr = UnityWebRequestAssetBundle.GetAssetBundle(uri, um.Crc);                 // 带 CRC（无版本 hash 时）
else
    uwr = UnityWebRequestAssetBundle.GetAssetBundle(uri, Hash128.Parse(um.Hash)); // ← 主流：走 Unity 缓存
uwr.timeout = 60; ...
```

字段定义（dump.cs，`AssetLoaderManifestAssetInfo`）：`Key/Type/Name(0x18)/Hash(0x20)/Crc(0x28)/Size(0x30)/AssetPaths/DownloadBundle`。

由以上可确认：
1. Bundle 的"是否需要下载"由 **`Caching.IsVersionCached(Name, Hash128(Hash))`** 决定——即 **Unity 原生缓存层的判定**；缓存目录就是 `UnityCache/Shared/<hash>/<hash>/__data`，与数据包给的 `<A>/<B>` 路径形态完全一致。
2. 主流下载/加载走 `GetAssetBundle(uri, Hash128)`：**该重载不带 CRC**，即游戏不做内容 CRC 校验（带 Crc 的只是无 hash 时的退化路径）→ 汉化修改过的 bundle 内容不会被内容校验拒绝。
3. 主数据表（非 bundle）判定就是 **`File.Exists(TempPath) && manifest.IsSameHash(Name)`** → 纯"文件存在"语义；这解释了 v1.0 root 版 `cp` 就能生效，且 patch 内容与原始 size 不同也不影响。
4. 游戏侧**没有**用 `<A>/<B>/__info` 自行校验的任何代码路径（内部缓存判定全部交给 Unity Caching）；汉化包也没有提供/要求 `__info`。

### 5.3 结论与证据强度

**结论：方案可行（游戏不会主动重下"已被判定为已缓存"的条目），前提是预置文件正好落在游戏期望的 `<A>/<B>/__data` 路径上（本数据包满足，A/B 即游戏上次真实下载生成的缓存哈希目录）。**

证据链（强 → 弱）：
1. **官方模块机制反编译（确证）**：LwLocal v1.3 全部 hook 只有 `Application.attach` 一处，之后只写文件、不 hook 任何加载/下载/校验。若"写文件"不足以让游戏命中，这个项目不可能以该形态连续发布 v1.0(root 复制)/v1.1/v1.2/v1.3 并成为推荐用法——这是"存在即命中"最直接的经验证据。
2. **游戏侧反汇编（确证）**：bundle 命中 = Unity `Caching.IsVersionCached`，主表命中 = `File.Exists`；下载路径是 `UnityWebRequestAssetBundle.GetAssetBundle(..., Hash128)`，无 CRC 校验。
3. **本工作区既有实测（间接）**：`tlw/归言录帧率解锁/README.md` 记录：清空 `UnityCache` 后游戏会停下弹"确认下载"框、不自动下载；把缓存回填后点 Cancel 即"直接进剧情，立绘背景正常"、缓存只涨 3MB → 游戏对 UnityCache 是"有就信、缺了才问"，不会主动扫描覆盖。
4. **本次模拟器首启实测（仅链路）**：安装 → 首启解包 430 items / 445 MB / 3.8s → 自动进游戏标题、无闪退（断网环境）→ 证明安装器链路 OK；断网不能证明"缓存被接受"，故不作 5.3 的正证据。

**残余风险（必须写进验收/说明）**：
- **R1（关键）**：Unity 6 原生 `Caching.IsVersionCached` 内部是否隐含要求 `__info` 元数据，我们**没有** 100% 反证（libunity.so 已 stripped，未做完整原生逆向）。若要求，则在线首启时 345 个 bundle 会被判未缓存 → 重新下载原版覆盖 `__data`（后果：汉化丢失；不闪退、不报错）。
  - 缓解/验证：**在线首启一次**（有网），观察 ① 标题/剧情是否中文；② `UnityCache/Shared` 里 `__data` 的 mtime 是否被改写、是否出现 `__info`、是否弹出"下载资源"对话框；③ 对比抽查 sha256 是否仍是汉化包的值。若被覆盖 → 回退方案：改用 LSPatch 模块路径，或进一步研究 `__info` 格式（不建议臆造）。
- **R2**：游戏大版本更新（1.57.0→新版）后，bundle hash/主表 hash 全变 → 旧数据全部失效，必须重做数据包（本 APK 绑定 1.57.0）。
- **R3**：游戏内"清除缓存"（`TitleCacheClearPopup`）会删 `UnityCache` → 汉化丢失。安装器 marker 应配合"数据存在性抽查"以便下次启动自动补装（§7）。
- **R4**：首启解包大文件（445 MB）耗时长（模拟器 3.8s，低端真机可能 10–30s+），必须在后台线程 + 进度 UI，禁止主线程 IO（ANR）。
- **R5**：空间：APK 内置 zip 445 MB + 落盘 445 MB ≈ 0.9 GB 额外占用，需预留 ≥1.5 GB 空闲。

---

## 6. 落盘期望清单（验收口径）

| 检查 | 期望值 |
|---|---|
| `files/cache/` 文件数 | **84**（83 表 + `manifest.json`；官方模块口径） |
| `files/cache/` 总字节 | 50,210,547 |
| `UnityCache/Shared/` 下 `__data` 文件数 | **345** |
| `UnityCache/Shared/` 总字节 | 395,024,307 |
| `UnityCache/Shared/` 下 `__info` 文件数 | **0**（不创建） |
| 两者合计文件数/字节 | 429 / 445,234,868 |
| `version.txt` 落盘 | 0（跳过） |
| 单文件写入方式 | 同目录 `.tmp` → delete 旧 → rename（可重跑） |

验收命令（模拟器已 root；`PKG=jp.goodsmile.touhoulostwordglobal_android`）：

```powershell
$adb='D:\Android\SDK\platform-tools\adb.exe'; $PKG='jp.goodsmile.touhoulostwordglobal_android'
# 1) 内部主数据表：84 个文件
& $adb shell "su -c 'ls -1 /data/data/$PKG/files/cache | wc -l'"
# 2) 外部 bundle：345 个 __data
& $adb shell "su -c 'find /sdcard/Android/data/$PKG/files/UnityCache/Shared -name __data | wc -l'"
& $adb shell "su -c 'find /sdcard/Android/data/$PKG/files/UnityCache/Shared -name __info | wc -l'"   # 期望 0
# 3) 字节数
& $adb shell "su -c 'du -sb /data/data/$PKG/files/cache /sdcard/Android/data/$PKG/files/UnityCache/Shared'"
# 4) 抽样 sha256（与 §4.4 / JSON 比对）
& $adb shell "su -c 'sha256sum /sdcard/Android/data/$PKG/files/UnityCache/Shared/006662e3887bc5d201623e96f723449b/b8fe0414e768623f57dbdc064105b65e/__data'"
& $adb shell "su -c 'sha256sum /data/data/$PKG/files/cache/077aacf7784f4f7354e7f716e3ec0bcf'"
# 5) 安装器 marker / 日志
& $adb shell "su -c 'cat /data/data/$PKG/files/tlw_cn/installed.txt'"
& $adb logcat -d -s TlwCn
```

---

## 7. 首启安装器：幂等 / 升级语义建议

### 7.1 marker（建议）

- 路径：`getFilesDir()/tlw_cn/installed.txt`（**不要**用官方模块的 `files/lwlocal.ver`，避免与官方模块语义混淆）。
- 内容推荐（纯 ASCII，单行）：
  `tlw-cn/1 data=v1.3-20261109b zip=a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792 files=429 bytes=445234868`
  - 现实现若 marker 取"zip 内 version.txt 文本"会得到 `v1.1-20261108`——功能上自比较无碍，但**语义误导**；建议改为 Release 版本号 `v1.3-20261109b`（或如上含 zip sha256 的复合串），并在 APK 升级数据包时同步改常量。
- 写入时机：**全部 429 个文件都成功落盘后**才用 `tmp → rename` 原子写 marker；任何异常不写。
- `skip_extract` / `no_autolaunch` 调试钩子保留（`files/tlw_cn/skip_extract`、`files/tlw_cn/no_autolaunch`）。

### 7.2 何时重装 / 何时跳过

| 启动时状态 | 动作 |
|---|---|
| marker 存在且版本串 == 当前常量 | 抽查：`files/cache` 文件数 ≥84 且 `UnityCache/Shared` 下 `__data` 数 ≥345 → **跳过**；否则视为缓存被清（R3）→ **重装**（覆盖写） |
| marker 缺失 / 版本串不同 / 上次中断（无 marker） | **重装**：全量覆盖写（**不需要**先删旧文件） |
| 解包失败 | UI 报错 + 重试按钮（原地重跑，幂等）；不得写 marker |

### 7.3 升级（数据包/游戏版本变化）

- **数据包升级（同一游戏版本）**：换新 zip、改安装器版本常量 → 首启全量覆盖写；旧数据中不在新 zip 的路径会残留（游戏按 hash 名寻址，残留目录不会被使用，**无害**；若在意空间，可记录安装清单 `files/tlw_cn/installed.list`（345 个 `<A>` + 84 个 master 文件名）用于回滚/清理）。
- **游戏大版本升级（1.57.0→新）**：整包数据作废，必须重新出 CN 数据包 + 重打包 APK；旧残留目录同样无害但占空间。
- **回滚**：删除本次安装清单里列出的文件即可（`files/cache/<name>` 与 `UnityCache/Shared/<A>/`），游戏缺失资源会自动重下；不要删整个 cache 目录里其它游戏文件。

### 7.4 与官方 v1.0/v1.3 的差异（我们的实现更严格）

| 点 | 官方 v1.3（模块） | 我们的内置安装器 |
|---|---|---|
| 写文件时机 | `Application.attach` 后台线程，与游戏启动并发（有竞态） | 游戏 Activity 启动前完成，**无竞态** |
| 数据来源 | 网络下载（4 源回退）/ 内部 `lwlocal_dl.zip` | APK `assets/lwlocal.zip` |
| 版本判定 | 远端 `version.txt` + `cache` 文件数>50（弱） | marker + 数据存在性抽查（更强） |
| 完整性 | 仅 Content-Length，无 sha256 | 建议构建期校验 zip sha256=a96657…（已知值） |
| 失败重试 | 下次进程启动重试，无 UI | UI 进度/错误/重试按钮 |
| `__info` | 不写 | 不写（保持一致） |
| 旧文件清理 | 不做 | 不做（幂等覆盖） |

---

## 8. 已知未汉化 / 质量注意项（来自作者 Release 说明，验收时不要误判为安装失败）

- 任务说明（如 `Log in on 5 days`）、部分 UI 标签（如 `Switch Effect`）仍为英文。
- 伙伴一览卡片角上的职业标记 `ATK/SUPP` 是图片，未替换；`Exchange`/`Errand` 按钮图为英文。
- 活动横幅为服务器下发图片，本地数据无法替换。
- 部分 TextMeshPro 界面可能出现中文方块（SDF 图集只烘焙了 80 个 ASCII 字符的历史问题；v1.1 起含 2 个字体包缓解）。
- 文本富文本标记（`<color>`、`{0}`、`\x1b` 玩家名占位）由数据包保留，验收时不要改动数据内容。

---

## 9. 相关文件与产物索引

| 路径 | 说明 |
|---|---|
| `integrated/docs/cn_data_inventory.json` | 机器可读台账（计数/字节/sha256/映射/5 个额外包/版本） |
| `work/cn-analysis/jadx-out/sources/lw/mod/LwLocalHook.java` | v1.3 模块反编译全文（462 行，唯一类） |
| `work/cn-analysis/jadx-out-12/` | v1.2 模块反编译（与 v1.3 代码逐行一致，仅 dex 路径注释不同） |
| `work/cn-analysis/il2cpp-out/dump.cs`、`script.json`、`stringliteral.json` | 游戏 IL2CPP 符号/方法/字符串（Il2CppDumper 6.7.46） |
| `work/cn-analysis/disasm_funcs.py`、`find_xrefs.py`、`parse_bundles.py` | 反汇编/交叉引用/UnityFS 头解析脚本 |
| `work/cn-analysis/extra_bundles/` | 5 个额外 bundle 的 UnityFS 文件与解析结论 |
| `work/cn-analysis/make_inventory.py` | 台账生成脚本（可重跑） |
