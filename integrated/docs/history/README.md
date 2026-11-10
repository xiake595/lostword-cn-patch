> 历史构建与验证记录（2026-11-09）：当时的密钥、机器路径和成品不随源码分发。当前入口见 [README](../../README.md)。

# 东方归言录（国际服）整合补丁：帧率解锁 + 简体汉化

把两个补丁项目合成**一个安装包**：

1. `tlw\归言录内置悬浮窗` —— 帧率解锁悬浮窗（注入 APK、内置 Java/dex、无 root）
2. `https://github.com/xiake595/lostword-cn-patch/releases/latest` v1.3 —— 国际服简体汉化数据（445 MB）

## 成品

| | |
|---|---|
| APK | `out\TLW-global-1.57.0-cn-fps.apk`（约 630 MB） |
| 基础游戏 | 国际服 **1.57.0**，versionCode **6728**，arm64-v8a，minSdk 24 |
| 包名 | `jp.goodsmile.touhoulostwordglobal_android`（**保持官方原值**） |
| 应用名 | `Touhou LostWord`（保持官方原值） |
| 签名 | `tlw-release.jks`（DN `CN=TLW FPS`，密码 `<本地签名密码>`），v1/v2/v3 |
| 内容 | 帧率悬浮窗 + 445 MB 汉化数据（首启自动解包） |

> **命名规范**：按「文件级等长替换」规范执行——包名、应用名、versionCode 全部沿用
> 官方原值，`resources.arsc` 一个字节都不重编码。这样既满足规范，也避免改 arsc 带来的
> 安装风险；唯一代价是必须卸掉官方客户端才能装（签名不同），这一点见「安装」。

## 集成方式

### 1. 帧率解锁（来自 `tlw\归言录内置悬浮窗`）

沿用原项目已经实测可用的做法：

- `classes3.dex` 注入 `tlw.fps.*`（`TlwBoot` ContentProvider 比 `Application` 更早启动，
  `UnityFps` 在 `libunity.so` 里找 `Application.targetFrameRate`，内置偏移 `0x199cc54`，
  扫不到时自动扫描；守护线程每秒回写，防止关卡加载时被游戏重置）
- 二进制 `AndroidManifest.xml` 注入 `<provider tlw.fps.TlwBoot>`（authority `tlw.fps.cn`）、
  `SYSTEM_ALERT_WINDOW` 权限，并给 Unity 启动 Activity 打开 `hardwareAccelerated`
- `assets\tlw_icon.png` 作为悬浮球图标

### 2. 简体汉化（来自 GitHub Release v1.3）

汉化数据是「本地资源替换」型的：84 个主数据表 + 345 个资源包，写进游戏自己的缓存目录后
由游戏直接读取（v1.0 的 root 脚本和 v1.1+ 的 LSPatch 模块都是这么做的）。

整合包里把整个数据包以 `assets/lwlocal.zip`（**STORED 不压缩**）内置进 APK，并新增
首启安装 Activity `tlw.cn.CnSetupActivity`：

| 数据包内路径 | 落盘位置 |
|---|---|
| `lwlocal/master/<file>`（84 项 = 83 张表 + manifest.json） | `getFilesDir()/cache/<file>` = `/data/data/<pkg>/files/cache/` |
| `lwlocal/bundles/<A>/<B>/__data`（345 项） | `getExternalFilesDir(null)/UnityCache/Shared/<A>/<B>/__data` = `/sdcard/Android/data/<pkg>/files/UnityCache/Shared/...` |
| `lwlocal/version.txt` | 只作兜底；实际 marker 用构建时写入的 `assets/tlw_cn.version`（= `v1.3-20261109b`） |

> 汉化数据包里 `lwlocal/version.txt` 是作者遗留的旧值 `v1.1-20261108`；构建脚本用
> `-CnVersion`（默认 `v1.3-20261109b+ci1`）生成 `assets/tlw_cn.version`，安装器优先读它——
> 这样 UI 显示的版本、以及「是否需要更新重装」的判断都以真实 Release 版本为准。
>
> **关键：每个资源包还要写 `__info`**。Unity 的 AssetBundle 缓存条目是 `__data` + `__info`
> 两件套，只写 `__data` 的目录会被游戏当成无效缓存清掉/重下（真机实测：345 个包 269 个被删、
> 76 个被英文原包覆盖 → 角色名/UI 回退英文）。安装器写出的 `__info` 与真机游戏自己下载产生的
> 文件逐字节同格式（纯文本 `-1\n<mtime 秒>\n1\n__data\n`）。详见
> [docs/INVESTIGATION-cn-cache-info.md](docs/INVESTIGATION-cn-cache-info.md)。

流程：**首次启动** → 显示深色进度界面 → 解包 445 MB 并写 345 个 `__info`（真机实测 1.5 s，
模拟器 4~9 s）→ 原子写 marker → 自动拉起游戏真正的启动 Activity
（`com.google.firebase.MessagingUnityPlayerActivity`）。之后每次启动命中 marker 直接进游戏；
marker 版本变化时自动走「更新重装」。

**兜底修复**：悬浮窗面板里有「缓存修复（汉化变英文时点这里）」按钮（`tlw.cn.CacheRepair`）。
游戏以后如果因为登录下载/版本更新/清缓存把汉化资源包冲掉（表现为角色名、UI 回退英文），
点一下它会删掉 marker、自动重启 App，重启后重新解包一遍汉化数据并进游戏；不需要 root/adb，
不动账号存档。实现见 `src/tlw/cn/CacheRepair.java`。

### 3. AndroidManifest 改动一览（全部为二进制 AXML 原地编辑）

| 改动 | 目的 |
|---|---|
| `+ <provider tlw.fps.TlwBoot authority=tlw.fps.cn>` | FPS 内核尽早启动 |
| `+ uses-permission SYSTEM_ALERT_WINDOW` | 悬浮球走系统悬浮窗（拖动不卡） |
| `- manifest/@requiredSplitTypes @splitTypes` | 合并 split 后能单 APK 安装 |
| Unity 启动 Activity `hardwareAccelerated=true` | 悬浮球 GPU 合成 |
| 原 Unity Activity 去掉 MAIN/LAUNCHER，新增 `tlw.cn.CnSetupActivity` 为 MAIN/LAUNCHER | 首启先装汉化数据再进游戏 |

## 安装

```powershell
# 1) 官方客户端还在的话先卸载（签名不同，无法覆盖安装；卸载会清数据）
adb uninstall jp.goodsmile.touhoulostwordglobal_android

# 2) 安装整合包
adb install out\TLW-global-1.57.0-cn-fps.apk

# 3) 首次启动：等进度条走完（445 MB），自动进游戏
```

- **从旧 FPS 包升级**（`TLW-global-1.57.0-fps.apk`，同包名同签名）：直接
  `adb install -r` 覆盖，存档/悬浮窗坐标/已下载资源全部保留，首次启动只需解包汉化数据。
- 安装前务必确认**引继码**已绑定（卸载官方会清本地数据）。
- 需要约 **1.1 GB 空闲空间**（APK 630 MB + 解包 445 MB），游戏自身资源另算。

## 构建

环境（本机）：

| 用途 | 路径 |
|---|---|
| JDK（javac/d8） | `D:\Android\Android Studio\jbr`（JDK 25） |
| Android SDK | `D:\Android\SDK`（platforms/android-36、build-tools/36.0.0） |
| Python | `python`（3.x） |
| R8/D8 | `r8.jar`（项目内，8.9.35） |

```powershell
cd D:\Codex_Project\Lostword\integrated
pwsh -File build-cn.ps1          # 约 40 秒出包（630 MB）
```

步骤：`javac --release 8` → `d8`（classes3.dex）→ AXML 编辑（provider/权限/split 属性/hw-accel/launcher）
→ `repack.py`（base + split lib + manifest + dex + icon + `assets/lwlocal.zip`，其余条目压缩方式原样保留）
→ `zipalign -p -f 4` → `apksigner` v1/v2/v3 → 自检打印。

参数（一般不用改）：`-Out`、`-BaseApk`、`-SplitApk`、`-CnZip`、`-Icon`、`-Authority`、
`-CnVersion`（写进 `assets/tlw_cn.version`，换汉化数据版本时一起改）。

## 验证记录（2026-11-09，最终包 v4 = __info 修复 + 缓存修复按钮）

构建产物：660,635,235 字节（630 MB），SHA-256 `F5FE95950C75442C83B4A94D3D4EBA41F36BEE7FFF8808E25BC689758FC8A32D`。

- **静态**：`aapt2 dump badging` 包名/6728/1.57.0/label `Touhou LostWord`/`tlw.cn.CnSetupActivity`/
  arm64-v8a 全部正确；`apksigner verify` 通过（v2+v3，证书 `CN=TLW FPS`）；`zipalign -c -p 4` 通过；
  4720 个条目，`resources.arsc`、`classes*.dex`、`assets/lwlocal.zip` 均 STORED；
  `classes3.dex` 含 `tlw.fps.*` + `tlw.cn.CnSetupActivity` + `tlw.cn.CacheRepair`；
  `assets/tlw_cn.version` = `v1.3-20261109b+ci1`。
- **真机实测**（Redmi 23127PN0CC / Android 16，全新安装 → 登录 → 让游戏下载完整资源）：
  - 发现问题：游戏下载完资源后角色名/UI 回退英文。排查结论 = 安装器只写了 Unity 缓存
    `__data`、没写 `__info`，缓存条目被游戏当垃圾清理/重下（详见
    [docs/INVESTIGATION-cn-cache-info.md](docs/INVESTIGATION-cn-cache-info.md)）。
  - 修复后重装（`adb install -r` 12 s）：
    `extract done: entries=430 seen=430 master=84 bundles=345 cacheInfo=345 bytes=445234854 elapsedMs=1500
    version=v1.3-20261109b+ci1`；缓存条目 4520 → **4789**（345 个汉化包全部就位、大小与数据包一致），
    游戏运行后无任何重新下载（`-newermt` 新文件 = 0）。
  - UI 对比：修复前 `Buddies/Journal/Items/Mail/Menu/Exchange/Errand…`
    → 修复后 `好友/图鉴/道具/邮箱/公告/商店/伙伴/绘卷/设施/任务/祈愿/探索…`，剧情台词中文、
    伙伴一览角色名中文（`绵月丰姬 / 茨木华扇 / 古明地觉 / 雾雨魔理沙 …`）。
    截图：`docs\screenshots\real-01-before-english.png`、`real-02-after-chinese-home.png`、
    `real-03-after-chinese-buddies.png`。
  - **「缓存修复」按钮实测**：面板点按钮 → `cache repair: marker deleted, relaunch scheduled, killing process`
    → 2.8 s 后 AlarmManager 自动拉起新进程 → `extract done ... cacheInfo=345 elapsedMs=943` →
    自动进游戏，UI 仍为中文，缓存 4789 项不变。截图 `real-04-repair-button.png`、
    `real-05-after-repair.png`，日志 `real-device-repair-logcat.txt`。
- **模拟器实测**（AVD `Medium_Phone`，Android 17/API 37.2，x86_64，断网）：
  - 安装/升级 OK；干净首启解包 `entries=430 seen=430 master=84 bundles=345 bytes=445234854`；
    进度/完成界面截图 `01-cn-install-progress.png`、`02-cn-install-done.png`；
  - 更新重装与快路径均正常（`04-update-reinstall.png`、`03-game-title-fps.png`），全程无 `FATAL EXCEPTION`。
- 证据：`work\device\REPORT.md`、`work\device\evidence\`、`work\cn-triage\`（真机取证）。
- 说明：`files/cache` 内部 84 项因设备无 root 无法直接列文件，由 `master=84` + 总字节守恒
  （445,234,854）+ 外部 345 项强校验间接确认。

## 已知限制与风险

1. **版本绑定**：汉化数据只对应国际服 1.57.0 / 6728。游戏更新后必须用新版 `base.apk` +
   `split_arm64.apk` + 对应版本汉化数据重新构建。
2. **登录后的资源下载**：已在真机上实测完整下载流程。原版安装器只写 `__data` 不写 `__info`，
   会被游戏当无效缓存清掉/重下（角色名、UI 回退英文）；已修复为同时写 `__info`，实测下载后
   汉化资源全部被游戏接受、没有重新下载。以后如果又出现回退英文，点悬浮窗里的
   「缓存修复」按钮即可自动重启重装（见 `docs/使用说明.md`）。
3. **16 KB page size 设备**：本包原生库来自官方 1.57.0（4 KB 对齐），在 16 KB 页设备上首次
   启动会出现系统兼容性提示（选 Don't show again 即可，游戏以兼容模式正常运行）。
4. **汉化数据包内部 `version.txt` 是作者遗留的 `v1.1-20261108`**（Release 资产 `version.txt`
   才是 `v1.3-20261109b`）；整合包用 `assets/tlw_cn.version`（`v1.3-20261109b+ci1`）做幂等标记，
   不影响内容。真实数据版本以 `lwlocal.zip` 的 SHA-256
   `a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792` 为准（v1.3）。
5. **不能与官方客户端共存**（同包名）；如需共存版可另出（等长改包名 `..._andr0id` +
   provider authority，钉死 41 字符/15 字节规范）。
6. 汉化数据版权归原作者/权利方；本项目仅作学习交流，后果自负。

## 目录结构

```
integrated\
  build-cn.ps1              一键构建（javac → d8 → manifest → repack → align → sign）
  src\tlw\fps\              帧率悬浮窗（原项目代码，未改）
  src\tlw\cn\CnSetupActivity.java   首启汉化数据安装器（UI + 解包 + 跳转）
  tools\axml.py             二进制 AXML 编辑（新增 set-launcher）
  tools\repack.py           原样重打包（新增大 asset 流式写入）
  assets\lwlocal.zip        汉化数据 v1.3（445 MB，STORED 进 APK）
  assets\tlw_icon.png       悬浮球图标
  apk\base.apk              国际服 1.57.0 base（107 MB）
  apk\split_arm64.apk       国际服 1.57.0 arm64 split（33 MB）
  tlw-release.jks           签名（与旧 FPS 包相同，可覆盖升级）
  r8.jar                    D8/R8
  docs\CN_DATA_SPEC.md      汉化数据安装语义分析（cn-analyst）
  docs\cn_data_inventory.json  数据清单/校验
  docs\screenshots\         模拟器验证截图 + logcat 摘录
docs\LOCALIZATION-errand-ui.md  派遣界面汉化源定位与替换思路（RE 报告，2026-11-09）
tools\re\                 UnityFS/LZ4 解包、UI 文本定位脚本
  docs\使用说明.md           面向最终用户的说明
  out\TLW-global-1.57.0-cn-fps.apk   成品（630 MB）
  out\SHA256.txt            成品校验信息
  out\build-*.log           历次构建日志（可删）
```

## 换新游戏版本怎么出包

1. 在干净设备上更新游戏，`adb pull` 新的 `base.apk` / `split_config.arm64_v8a.apk` 到 `apk\`；
2. 到汉化项目 Releases 取对应版本的新 `lwlocal.zip` 覆盖 `assets\lwlocal.zip`，
   并把 Release 的 `version.txt` 内容传给 `build-cn.ps1 -CnVersion "vX.Y-YYYYMMDDx"`；
3. 确认启动 Activity 名（`aapt2 dump badging`）后跑 `build-cn.ps1`；
4. 用新版本号命名产物，按「验证记录」的静态检查 + 模拟器冒烟走一遍。

## 可转移项目包（不含成品 APK）

`D:/Codex_Project/Lostword/transfer/TLW-cn-fps-project/`（597 MB，压缩包 `TLW-cn-fps-project-v4.7z`）
是本工程的完整可重建副本：源码 + tools + 构建输入（官方 base/split + 汉化数据 zip）+ 签名 + 文档，
**不含成品 APK 与 build 中间产物**。`build-cn.ps1` 已改成自动探测 JDK/SDK/Python
（可用 `-JdkHome` / `-SdkRoot` / `-PythonExe` 覆盖），换机器直接 `pwsh -File build-cn.ps1` 即可出包；
包内附 `TRANSFER.md`（转移/重建说明）、`SHA256SUMS.txt` 与 `verify-files.ps1`（完整性校验）。
