# 1.58.0 + 汉化 v1.4 共存版（ci3）出包与兜底记录

> 时间：2026-11-11。输入：官方设备拉取的 1.58.0 base/split + 上游 v1.4 数据包。
> 产物：`out\TLW-global-1.58.0-cn-fps-coexist.apk`，**592,281,182 B（564.8 MB）**，
> SHA-256 `70C90972EF3750E883862EE5B6DFC67F4A1ACEEE8ACD7FF6EFD3EA028634D74A`。

## 一、为什么出共存版

HyperOS 真机上的旧改版（原包名、1.57 时代 v1.3 数据 → 升 1.58 后点「缓存修复」）会黑屏：
1.57 的 84 张主表里有 14 张是 1.58 已弃用的（商店/任务相关），旧表留在 `files/cache`，
1.58 客户端按新结构读旧表 → `NullReferenceException` → 商店/主界面黑屏。
上游 `cn/1.58-and-prune` 分支已给安装器加「按清单清理旧条目」，但**从 ci1（没有清单）升级时
第一次清不掉**；且同包名重装会覆盖官方客户端、必须卸载官方。因此新增：

- **共存版包名**：`jp.goodsmile.touhoulostwordglobal_andr0id`（沿用 fps-unlock 作者共存版的
  等长改名，`android`→`andr0id`，41 字符；`resources.arsc` 只做等长字节替换，不重编码）
- **应用名**：`TLW CN FPS Mod!`（15 字节，与 `Touhou LostWord` 等长）
- **authority**：`tlw.fps.cn.coexist`（避免与官方/旧补丁的 provider 冲突）

## 二、ci3 改了什么

| 改动 | 文件 | 行为 |
|---|---|---|
| 旧版残留清理 | `src/tlw/cn/CnSetupActivity.java` + `assets/tlw_cn_legacy.txt` | 内置 v1.3 写过、v1.4 已不带的 14 个主表文件名；每次解包时删掉仍存在且不在本版数据包里的那些。**只删清单内的文件，游戏自己下载的不碰** |
| 游戏版本校验 | 同上 + `assets/tlw_cn.game` | 数据包标记 `game=1.58.0`；与客户端 `versionName` 不一致时**拒绝解包**并提示，避免旧表写进新客户端再次黑屏 |
| 还原官方缓存 | `src/tlw/cn/CacheRestore.java`、`src/tlw/fps/FpsOverlay.java` | 悬浮窗新增「还原官方缓存（黑屏/进不去时点这里）」：按 `installed.list`/`installed.bundles`/legacy 清单删除汉化数据，写 `restore_mode` 后自动重启；重启后跳过解包直接进游戏，由游戏重下官方数据 |
| 缓存修复补齐 | `src/tlw/cn/CacheRepair.java` | 「缓存修复」在删 marker/钩子之外**同时删除 `restore_mode`**，保证还原官方后还能装回汉化 |
| 解包失败兜底 | `CnSetupActivity` | 失败界面新增「跳过汉化，直接启动游戏」：写 `skip_extract` 钩子并启动游戏，装不上也能玩官方版；之后点「缓存修复」可清钩子重装 |
| 构建脚本 | `build-cn.ps1` | 新增 `-Pkg/-OldPkg/-Label/-OldLabel/-GameVersion/-LegacyList`；clone 步骤 + `repack.py -arsc` 换入等长改名的 `resources.arsc`；Step 7 校验包名/应用名 |

## 三、构建命令

```powershell
$env:TLW_KEYSTORE_PASSWORD = '...'
cd integrated
.\build-cn.ps1 -Pkg "jp.goodsmile.touhoulostwordglobal_andr0id" `
  -Label "TLW CN FPS Mod!" -Authority "tlw.fps.cn.coexist" `
  -Out "out\TLW-global-1.58.0-cn-fps-coexist.apk"
```

输入：`apk/1580/base.apk`（106,395,872 B）+ `apk/1580/split_arm64.apk`（33,465,561 B），
`assets/lwlocal.zip` = v1.4（378,134,402 B，sha256 `9b6f1c90…c7e2`，761 条目 / 438,036,025 B）。

构建耗时约 32 秒；`aapt2 dump badging` 复核：
`package name='jp.goodsmile.touhoulostwordglobal_andr0id' versionCode='7016' versionName='1.58.0'`、
`application-label:'TLW CN FPS Mod!'`、`launchable-activity: tlw.cn.CnSetupActivity`、`native-code: arm64-v8a`；
`apksigner verify` / `zipalign -c -p 4` 通过；APK 4717 条目。

## 四、HyperOS 真机实测（2026-11-11）

设备 `dd3e0d04`（Redmi 23127PN0CC / HyperOS 3.0 / Android 16），`adb install -r` 14.4 秒 Success。

首启（全新共存包，无缓存迁移）：

```
I TlwCn : onCreate filesDir=/data/user/0/…_andr0id/files extRoot=/storage/emulated/0/Android/data/…_andr0id/files skipExtract=false noAutolaunch=false
I TlwCn : probeAsset: zipPresent=true version=v1.4-20261110b+ci3 game=1.58.0 legacy=14
I TlwCn : extract start: …
I TlwCn : data pack version.txt = [v1.4-20261110b]
I TlwCn : marker written: …/tlw_cn/installed.txt = v1.4-20261110b+ci3
I TlwCn : extract done: entries=416 seen=761 master=70 bundles=345 cacheInfo=345 packagedInfo=345
          prunedLegacy=0 prunedMaster=0 prunedBundles=0 bytes=438028075 elapsedMs=23706
I TlwCn : game activity started: com.google.firebase.MessagingUnityPlayerActivity
I TlwFps: attach base=0x755fee6000 views=1 tfr=0x199cc54 writable=true via 内置 1.58.0
```

- 解包 23.7 秒（真机外部存储比 MuMu 慢，属正常）；缓存 345 个 `__data` / 346 个 `__info`（含 `Shared/__info`），共约 395 MB
- 第二次启动走快路径：`up-to-date: marker=v1.4-20261110b+ci3 zipVersion=v1.4-20261110b+ci3` → 直接进游戏
- 标题界面 `Version 1.58.0` 正常显示，FPS 悬浮球 `120` 正常，无 `FATAL EXCEPTION` / ANR
- 共存包是独立 App（数据目录 `/…_andr0id/`），与设备上原包名的旧改版/官方客户端互不影响；
  首次进游戏需**手动登录（引继）并由游戏下载资源**，本记录未做登录与资源下载验证

## 五、兜底操作流程（用户侧）

| 现象 | 操作 |
|---|---|
| 汉化回退英文 | 悬浮窗 →「缓存修复」→ 自动重启并重装 v1.4 汉化数据 |
| 黑屏 / 进不去主界面 | 悬浮窗 →「还原官方缓存」→ 自动重启进游戏（跳过汉化），游戏重下官方数据；之后想恢复汉化再点「缓存修复」 |
| 解包失败（存储不足/数据损坏） | 失败界面点「跳过汉化，直接启动游戏」先保证能玩；修好存储后点「缓存修复」重装 |
| 数据包与游戏版本不符 | 安装器直接拒绝并提示，不会写坏缓存；换对应版本的整合包 |

## 六、已知限制

- 共存包无法覆盖官方客户端（包名/签名都不同），反之亦然；账号靠引继，本地数据不迁移。
- v1.4 的任务/交换所主表保持英文（上游设计）；1.58 新增 `another`/`event78` 未翻译。
- 若游戏再升级（versionCode 变化），需拉新 base/split + 上游新数据包，并把 `-GameVersion` 改到新版本；`UnityFps` 的 `KNOWN_VER` 也要确认新版本在后。

## 七、证据

- docs/screenshots-1580-coexist/01-coexist-title-1.58.0.png：共存版标题界面（Version 1.58.0、FPS 悬浮球 120）
- docs/screenshots-1580-coexist/02-first-launch-logcat.txt：首启解包日志（entries=416 seen=761 master=70 bundles=345，24 秒）
- docs/screenshots-1580-coexist/03-fps-logcat.txt：FPS 附着日志（via 内置 1.58.0，tfr=0x199cc54）
- docs/screenshots-1580-coexist/04-second-launch-fastpath-logcat.txt：二次启动快路径日志（up-to-date）
