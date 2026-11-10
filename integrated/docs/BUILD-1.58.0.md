# 1.58.0 出包记录（2026-11-10）

> 输入：`C:\Users\Quan\Documents\MuMu共享文件夹\lw\{base-7016.apk, split-7016-0.apk}`
> 版本：国际服 **1.58.0 / versionCode 7016**，arm64-v8a，minSdk 24 / targetSdk 36
> 结论：**两个包都出了，装进 MuMu 跑通**；但**汉化数据是 1.57.0 的，对 1.58.0 基本无效**（详见第三节）。

---

## 一、产物

| 文件 | 大小 | SHA-256 | 说明 |
|---|---|---|---|
| `out\TLW-global-1.58.0-cn-fps.apk` | 659,385,816 (628.8 MB) | `4DC8B05E18AE154BD9C45E38085E67BBDDFC7C5CE995E020C2895751ACCB2A87` | **解帧 + 汉化（数据为 1.57.0 版）** |
| `out\TLW-global-1.58.0-fps.apk` | 214,023,509 (204.1 MB) | `C7A8882CDA0D5FE0F0B8CC99C760D9B5BC688B18B5042C84FED1F9D27AD8C785` | **只解帧**（不带汉化，干净） |
| `out\TLW-global-1.57.0-cn-fps.apk` | 660,635,235 (630 MB) | `F5FE9595…A32D` | 上一版，保留不动 |

签名都是 `CN=TLW FPS`（`tlw-release.jks`，v1+v2+v3），同包名同签名 → **可以直接覆盖安装 1.57.0 的包**，存档保留。

## 二、构建做了什么

1. 输入归档：`apk\1570\`（旧）与 `apk\1580\`（新），`base.apk` / `split_arm64.apk` 各一份。
2. `build-local.ps1` 新增透传参数 `-BaseApk / -SplitApk / -CnZip / -CnVersion`（不动 `build-cn.ps1` 原件）。
3. 静态核对：启动 Activity 仍是 `com.google.firebase.MessagingUnityPlayerActivity`；`requiredSplitTypes=base__abi`、`splitTypes=""`、`hardwareAccelerated=false` 三处与 1.57.0 一致 → AXML 五个补丁全部命中（provider / 权限 / 两个 split 属性 / hw-accel / launcher 切换）。
4. `libunity.so` 与 1.57.0 **逐字节相同**（`57d8b14b…`，26,914,664 B）→ `targetFrameRate` 偏移 `0x199cc54` 仍然有效（`tools\check_offset.py` 读出来 `-1`，OK）。
5. 新 base 的 dex 只有 `classes.dex` + `classes2.dex` → 注入 `classes3.dex` 不冲突。
6. 新增 `KNOWN_VER` 里的 `"1.58.0"`（原来只有 `1.57.0` / `1.71.1`），否则每次启动都会走 `scan()` 扫描而不是直接用内置偏移。
7. 成品比对：4711 个条目与 1.58.0 base/split **逐字节相同**，只有 `AndroidManifest.xml` + `META-INF/MANIFEST.MF` 变化；新增仅 `assets/lwlocal.zip`、`assets/tlw_cn.version`、`assets/tlw_icon.png`、`classes3.dex`、`META-INF/TLW.*`。

## 三、⚠️ 汉化数据对 1.58.0 无效（重点）

上游 `lostword-cn-patch` **最新仍是 v1.3（2026-11-09）**，没有出 1.58.0 的数据包（查过 Releases API 与提交历史）。
`docs\CN_DATA_SPEC.md` §R2 早就写明：**游戏大版本更新后 bundle hash / 主表 hash 全变，旧数据全部失效，必须重做数据包**。

MuMu 实测（装 `1.58.0-cn-fps` 后，16:42 解包 → 点 Game Start 下载完 200 MB）：

| 检查项 | 结果 |
|---|---|
| 84 个主数据表文件 | 全部写进 `files/cache`，文件名还在，**但 37 个被游戏用 1.58.0 的原版覆盖**（大小/哈希都变了，例 `07ab80f4…` 2,921,120 → 2,895,424 B） |
| 345 个汉化资源包 | **0 个存活**（`UnityCache/Shared/<A>/<B>` 目录名对不上 1.58.0 的 hash，游戏全部重下成英文原包） |
| 界面实际表现 | 顶栏「好友/图鉴/道具/邮箱/公告」等主表字段仍是中文（46 张表没被覆盖的部分），但**剧情台词、角色名、按钮图全是英文**（截图 `docs\screenshots-1580\02-home-partial-cn.png`） |

所以：**想要 1.58.0 的中文，必须等上游出对应版本的数据包**（或者自己做，见第五节）。

## 四、真机/模拟器验证（MuMu `127.0.0.1:7555`，Android 12，arm64 翻译）

```
16:56:52.070 I TlwFps : installed
16:56:52.153 I TlwCn  : probeAsset: zipPresent=true version=v1.3-20261109b+ci1-1580
16:56:52.154 I TlwCn  : up-to-date: marker=… zipVersion=…          ← 快路径，不重复解包
16:56:52.170 I TlwCn  : game activity started: …MessagingUnityPlayerActivity
16:56:52.839 I TlwFps : attach base=0x3114000 views=1 tfr=0x199cc54 writable=true via 内置 1.58.0
```

- 安装：`adb install -r` 30.9 s **Success**（从 1.57.0 直接覆盖升级，数据保留）
- 首启：解包 430 项 / 445,234,854 B / **2.8 s**，`cacheInfo=345`，marker `v1.3-20261109b+ci1-1580`
- 游戏：到标题界面 `Version 1.58.0`（截图 `docs\screenshots-1580\01-title-1.58.0.png`），**无 FATAL EXCEPTION**，悬浮球在左上角正常显示 `20`（当前帧率）
- 下载提示 200.1 MB → 确认 → 下载完成进大厅（截图 02）
- FPS：`via 内置 1.58.0` = 直接用内置偏移，写入可写（`writable=true`）

## 五、要 1.58.0 汉化怎么办

1. **等上游**：<https://github.com/xiake595/lostword-cn-patch/releases> 出 1.58.0 对应数据包，然后
   `build-local.ps1 -BaseApk apk\1580\base.apk -SplitApk apk\1580\split_arm64.apk -CnZip <新zip> -CnVersion <新版本号>`
   重新出包（30 秒）。
2. **自己做数据包**（工作量大，但路径清楚）：主表 = 84 个 JSON（`files/cache/<md5>`，游戏按 `File.Exists` + 清单 hash 判定，改内容不影响命中）；资源包 = 345 个 UnityFS bundle，**必须用 1.58.0 的原包做底**再替换文本，因为 `<A>/<B>` 目录名是 1.58.0 的 hash。1.57.0 的 bundle 拿到 1.58.0 上会因为 hash 不匹配被当垃圾清掉（本次实测 345 个全灭）。
3. 短期折中：装 `TLW-global-1.58.0-fps.apk`（只有解帧、204 MB），等汉化数据，别背着一个 630 MB 的半中文包。

## 六、回滚

- 想回 1.57.0：直接装 `out\TLW-global-1.57.0-cn-fps.apk`（同签名，`adb install -r`；但**降级 versionCode 会被系统拒绝**，需要先 `adb uninstall` —— 会清本地数据，先绑引继码）。
- 想回官方：卸掉本包，装官方 1.58.0，用引继码登录。
