# 合并版：简体汉化 + 帧率悬浮窗

一个重打包 APK 内含 FPS 悬浮窗与汉化数据。首启由 `tlw.cn.CnSetupActivity` 在游戏进程内解包汉化数据，然后进入游戏；以后按版本标记走快速启动。不需要 root、ADB 或 LSPatch 来运行成品。

当前基线：国际服 **1.58.0 / 7016 / arm64-v8a / Android 7.0+**，汉化数据 **v1.4**（70 张主表 + 345 个资源包）。默认保留官方包名、应用名及 `resources.arsc`；也可用 `-Pkg` 做**等长改名**，构建与官方客户端并存的版本（沿用 fps-unlock 作者共存版的包名 `jp.goodsmile.touhoulostwordglobal_andr0id`）。签名改变，同包名无法覆盖官方客户端。

## 构建

按 [构建准备](../docs/BUILDING.md) 配置 JDK、Android SDK、Python、R8 与本地签名。另行准备：

| 本地路径 | 输入 |
|---|---|
| `apk/1580/base.apk` | 官方国际服 1.58.0 base（`adb pull` 或自行取得） |
| `apk/1580/split_arm64.apk` | 同一版本 arm64 ABI split |
| `assets/lwlocal.zip` | [v1.4 Release](https://github.com/xiake595/lostword-cn-patch/releases/tag/v1.4) 汉化数据（378,134,402 B，sha256 `9b6f1c90…c7e2`） |
| `assets/tlw_icon.png` | 仓库内必要悬浮球图标 |
| `assets/tlw_cn_legacy.txt` | 仓库内旧版（v1.3/ci1）主表文件名清单，用于升级时清理残留旧表 |

在本目录运行（覆盖官方包名的版本）：

```powershell
$env:TLW_KEYSTORE_PASSWORD = Read-Host '本地签名密码'
.\build-cn.ps1 -JdkHome $env:JAVA_HOME -SdkRoot $env:ANDROID_SDK_ROOT -PythonExe python `
  -R8Jar '本地的r8.jar路径' -KeyStore '本地的签名.jks路径'
```

构建**共存版**（与官方客户端并存，包名/应用名等长替换，`resources.arsc` 不重编码）：

```powershell
$env:TLW_KEYSTORE_PASSWORD = '本地签名密码'
.\build-cn.ps1 -Pkg "jp.goodsmile.touhoulostwordglobal_andr0id" `
  -Label "TLW CN FPS Mod!" -Authority "tlw.fps.cn.coexist" `
  -Out "out\TLW-global-1.58.0-cn-fps-coexist.apk"
```

可指定 `-KeyAlias`、`-Out`、`-BaseApk`、`-SplitApk`、`-CnZip`、`-Icon`、`-Authority`、`-CnVersion`、`-GameVersion`。默认数据标记 `v1.4-20261110b+ci3`，`-GameVersion 1.58.0` 会写入 `assets/tlw_cn.game` 供安装器做版本校验。

流水线：javac → D8 → 二进制 AXML 修改 → （可选）等长改包名/应用名 → 合并 base/split、dex、图标与数据 → zipalign → apksigner。数据包与签名密钥、原始 APK、生成产物均不进入 Git。

## 使用与修复

安装前确认账号引继方式并备份必要数据。卸载官方客户端会删除本地数据；不同签名无法覆盖升级。使用同一份本地签名的旧补丁可尝试覆盖安装，但需确保游戏版本兼容。共存版是另一个 App（数据不迁移），首次进入需要重新登录并下载资源。

首次启动等待汉化解包完成（1.58 真机实测约 24 秒），后续直接进入游戏。Unity 缓存会同时写 `__data` 和 `__info`。

悬浮窗面板有两个应急入口（ci3 起）：

| 按钮 | 作用 |
|---|---|
| **缓存修复（汉化变英文时点这里）** | 删安装标记、清 `restore_mode`/调试钩子，重启后重新解包汉化数据 |
| **还原官方缓存（黑屏/进不去时点这里）** | 删掉安装器写过的汉化主表与资源包（只删自己写过的），写下 `restore_mode` 并重启；重启后跳过解包直接进游戏，由游戏重新下载官方数据。想恢复汉化再点「缓存修复」 |

安装器另有两条兜底：① 数据包与客户端 `versionName` 不一致时**拒绝解包**并提示（避免旧表写进新客户端导致黑屏）；② 解包失败界面提供「跳过汉化，直接启动游戏」（写入 `skip_extract`，之后不再自动解包，点「缓存修复」可恢复）。

升级时安装器会按 `installed.list` / `installed.bundles` 清掉「上次写过、这次数据包里没有」的旧表/旧包；对更早的 v1.3/ci1 装机（没有清单）则用内置 `assets/tlw_cn_legacy.txt` 兜底清理——这正是 1.57→1.58 升级后商店面板黑屏（旧 84 张表残留）的根因修复，见 [故障排查](docs/TROUBLESHOOT-shop-black-screen.md)。

出包与实测记录见 [1.58.0 + v1.4 记录](docs/BUILD-1.58.0-v14.md)、[共存版 ci3 记录](docs/BUILD-1.58.0-coexist-ci3.md)。`src/tlw/cn` 与 `cn-patch/src/tlw/cn` 为相同安装器的源码副本；`src/tlw/fps` 包含合并版特有的缓存修复/还原入口。

## 已知限制（v1.4 自带）

- 任务（课题）与交换所/商店主表**故意保持英文**，避免 1.58 表结构变动再次引发黑屏。
- 1.58 新增 `another` / `event78` 剧情篇章尚未翻译。
- 卡片职业标记 `ATK/SUPP/SPD`、`Exchange`/`Errand` 按钮图是图片资源，上游未替换；派遣界面 `Completed Errands` 等文本缺 218d2488 资源包，见 [派遣 UI 分析](../cn-patch/docs/LOCALIZATION-errand-ui.md)。
