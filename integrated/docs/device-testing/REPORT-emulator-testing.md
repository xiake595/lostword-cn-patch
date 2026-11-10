# TLW 模拟器安装 / 启动不闪退验证报告（device-tester）

> 验证目标（用户硬性要求）：**只验证「APK 能安装 + 游戏能启动且不立即闪退」**，不登录、不触发游戏资源下载。
> 最终包：`integrated\out\TLW-global-1.57.0-cn-fps.apk`（v3，2026-11-09 15:45:50，660,631,139 bytes，sha256 `43CBC2D6…C9E3`）
> 结论：**v3 全部 PASS** —— 升级安装、版本升级触发的「更新重装」（UI：v1.1-20261108 → v1.3-20261109b；日志 430/430、master=84、bundles=345、445,234,854 bytes、version=v1.3-20261109b）、随后快路径 `up-to-date`、自动进游戏到标题界面、无 FATAL、进程存活；全程断网，未点登录/Game Start，未触发下载。

本报告随验证持续更新；最近更新：v3 最终复测（2 轮启动）。

---

## 1. 环境

| 项 | 值 |
|---|---|
| AVD | `Medium_Phone`（`D:\Android\AVD`） |
| 系统镜像 | `android-37.2 google_apis_playstore_ps16k x86_64`（**Android 17 / API 37.2**） |
| ABI | `x86_64, arm64-v8a`（`libndk_translation.so` ARM 翻译可用，arm64-v8a 游戏可运行） |
| Page size | **16384（16KB）** —— 会触发系统 16KB 兼容提示（见风险 R1） |
| Build | `ro.build.type=user`, `ro.debuggable=0`，**adb root 不可用**（production build） |
| /data | 10G，初始剩余 ~4.3G；v3 解包完成后剩余 **2.5G** |
| 网络 | 全程断网：`svc wifi disable` + `settings put global airplane_mode_on 1`，`ping 8.8.8.8` = `Network is unreachable` |
| 当前已装 | `jp.goodsmile.touhoulostwordglobal_android` 1.57.0 (6728)，v3 APK（lastUpdateTime 07:47:04） |

## 2. 脚本（work\device\，阶段 2 可直接复用）

| 文件 | 说明 |
|---|---|
| `boot.ps1` | 启动/等待模拟器（boot_completed + PackageManager 就绪）、断网、打印设备摘要。已验证 `-NoStart` 路径 |
| `net-off.sh` | 设备侧断网脚本（wifi/data/飞行模式 + 连通性自检），由 boot.ps1 push 执行 |
| `install-and-check.ps1` | 断网 → `adb install -r` 计时 → 启动 → 观察 N 秒 → 自动点掉系统弹窗（16KB 兼容/沉浸/权限）→ 截图 + logcat + FATAL 判定 → force-stop。已自测 |
| `pull-evidence.ps1` | 设备侧取证：包信息、df、diskstats、外部目录树/条目数、logcat、截图。已自测（`evidence\pull-phase2-final\`） |
| `evidence\` | 全部截图 / logcat / 安装日志 |

## 3. 阶段 1（基线，验证模拟器通路）

| 包 | 结果 |
|---|---|
| 旧 FPS 版 `tlw\归言录内置悬浮窗\out\TLW-global-1.57.0-fps.apk`（215MB） | `adb install -r` **17.8s Success**；启动后 Unity 正常渲染、TlwFps 悬浮窗显示 60fps、到达标题界面；无 FATAL；已 force-stop |
| 管线 stub 包（660MB，占位 CnSetupActivity 直接拉 Unity） | install **14.7s Success**；`TlwCn: stub CnSetupActivity: launching game activity` → 2.96s 拉起 Unity → 标题界面；无 FATAL；已 force-stop |

首次启动该系统上会弹两个**系统**窗口（与游戏无关）：① 16KB 兼容提示（RELRO not aligned）② 沉浸全屏提示（Got it）。均已处理（16KB 选 Don't Show Again / 点 Got it），之后启动不再出现。`pm clear` 后 16KB 提示会重新出现（属系统行为）。

## 4. 阶段 2 v1 最终包（2026-11-09 15:29 构建，sha256 `55C72D89…E26AC`）

- `adb install -r`：**16.3s Success**（同签名同版本升级，保留旧数据）。
- 启动：`onCreate … skipExtract=false noAutolaunch=false` → `extract start` → `extract done: entries=430 bytes=445234854 elapsedMs=3839` → `marker written: …/files/tlw_cn/installed.txt` → `game activity started` → 约 20s 进入标题界面。
- 未触发下载：全程断网；外部数据目录仅 CN 数据（398M）。
- 已 force-stop。

## 5. 阶段 2 v2 复测（2026-11-09 15:37 构建，manifest.json 也写入 files/cache）

安装：**`adb install -r` 11.9s Success**（`evidence\v2-install.log`）。

### A. 升级 + 快路径（marker 已存在）——**PASS**
- logcat TlwCn：`up-to-date: marker=v1.1-20261108 zipVersion=v1.1-20261108`，**无 `extract start`**；`game activity started`。
- 到标题界面（`evidence\v2-A-quickpath-title.png`），pid 存活、无 FATAL，已 force-stop。

### B. 干净首启 + 真实解包（no_autolaunch）——**PASS**
- 步骤：`pm clear` → 外部钩子 `mkdir -p .../files/tlw_cn; touch .../no_autolaunch` → 启动。
- 关键日志（`evidence\v2-B-logcat-tlwcn.txt`）：
  ```
  I/TlwCn: debug hook (external): /storage/emulated/0/Android/data/jp.goodsmile.touhoulostwordglobal_android/files/tlw_cn/no_autolaunch
  I/TlwCn: onCreate … skipExtract=false noAutolaunch=true
  I/TlwCn: probeAsset: zipPresent=true version=v1.1-20261108
  I/TlwCn: extract start: …
  I/TlwCn: extract done: entries=430 seen=430 master=84 bundles=345 bytes=445234854 elapsedMs=3955 version=v1.1-20261108
  I/TlwCn: marker written: …/files/tlw_cn/installed.txt = v1.1-20261108
  I/TlwCn: no_autolaunch hook: stay on done screen
  ```
- UI：进度界面「东方归言录 汉化安装」**67%/65%**（281/430、293.0MB/445.2MB，`v2-B-progress-1.png`）；完成后停在「汉化资源安装完成 100% 已安装 430 个文件（445.2 MB）耗时 4.0 秒 资源版本 v1.1-20261108 / 调试钩子 no_autolaunch 生效：本次未自动启动游戏」（`v2-B-done.png`）。
- 未启动游戏：`topResumedActivity = tlw.cn.CnSetupActivity`（非 Unity），pid 存活、无 FATAL；已 force-stop（未启动游戏）。
- 数据校验：
  - `ls UnityCache/Shared | wc -l` = **346**（345 目录 + 游戏自建 `__info` 文件）；`find -maxdepth 1 -type d` = **345**；`find -name __data` = **345**。
  - 外部 `__data` 字节和 = **395,024,307**，与 `integrated\docs\cn_data_inventory.json` 的 `bundle_bytes` **完全相等**。
  - 抽样 3 个 `__data` 的 sha256 与 inventory 完全一致（`unpack-verify.txt`）。
  - `du -sk .../files` = 407,516 KB（约 398M，= CN 数据 + 游戏自建目录；未发生资源下载）。
  - 总解包量 `bytes=445234854` = inventory `total_uncompressed_bytes 445234868 - version.txt 14`，**完全对上**；`master=84`（含 manifest.json，v2 新增行为已生效）、`bundles=345`。

### C. 快路径回归 + 游戏启动不闪退——**PASS**
- 删除外部 `no_autolaunch` → 启动：`up-to-date: marker=… zipVersion=…`（无 extract，无 UI）→ `game activity started` → 约 20s 到标题界面（`v2-C-title.png`）；pid 存活、无 FATAL；已 force-stop。
- 之后 `df /data` 剩余 3.1G。

## 6. 阶段 2 v3 最终复测（version 标记改用 assets/tlw_cn.version = v1.3-20261109b）

v3 包：660,631,139 bytes / 15:45:50 / sha256 `43CBC2D6FC679767B63B691C989C65FEFC82EA8BD8410D019C1B62AD6AD7C9E3`；`assets/tlw_cn.version` 内容 = `v1.3-20261109b`（15 bytes）；`assets/lwlocal.zip` 未变（sha256 A96657BF…0792）；包名/版本/launcher/签名均未变。
`adb install -r`：**21.6s Success**。安装后设备上 marker 仍是 v1.1-20261108（v2 遗留）→ 正好触发升级路径。

### 启动第 1 次（更新重装）——**PASS**
关键日志（`evidence\v3-launch1-logcat-tlwcn.txt`）：
```
I/TlwCn: probeAsset: zipPresent=true version=v1.3-20261109b
I/TlwCn: extract start: …            ← 虽然 marker 已存在，仍触发重装（升级路径生效）
I/TlwCn: data pack version.txt = [v1.1-20261108]   ← 只是 zip 内数据包元数据，不再用于 marker
I/TlwCn: marker written: …/files/tlw_cn/installed.txt = v1.3-20261109b
I/TlwCn: extract done: entries=430 seen=430 master=84 bundles=345 bytes=445234854 elapsedMs=9106 version=v1.3-20261109b
I/TlwCn: game activity started: com.google.firebase.MessagingUnityPlayerActivity
```
UI（`evidence\v3-launch1-progress-1.png`）显示：
**「检测到汉化数据更新（v1.1-20261108 → v1.3-20261109b），正在重新安装…」19%，文件 111/430 · 87.5 MB / 约 445.2 MB**。
→ 解包完成自动进游戏，约 20s 到标题界面（`v3-launch1-title.png`）；pid 23260 存活、无 FATAL；已 force-stop。
> 注：该中文提示是 **UI 文案**，不是 TlwCn 日志行（logcat 里没有原文），判定依据 = `probe version=v1.3` + marker 存在却仍 `extract start` + `extract done version=v1.3` + 该截图。

### 启动第 2 次（快路径）——**PASS**
```
I/TlwCn: probeAsset: zipPresent=true version=v1.3-20261109b
I/TlwCn: up-to-date: marker=v1.3-20261109b zipVersion=v1.3-20261109b
I/TlwCn: game activity started: com.google.firebase.MessagingUnityPlayerActivity
```
无 `extract start`、无 UI，直接进 Unity → 约 20s 到标题界面（`v3-launch2-title.png`）；pid 24246 存活、无 FATAL；已 force-stop。
外部数据最终校验：`__data`=345、目录=345（entries 346 含游戏自建 `__info`）、字节和=**395,024,307**（与 inventory 一致）；`df /data` 剩 2.5G；airplane=1、ping 不可达。

## 7. 约束遵守

- 全程断网（wifi disabled + airplane_mode_on=1 + ping 不可达），未登录、未点 Game Start/任何进入游戏按钮，未触发资源下载（外部数据仅 CN 包 + 游戏自建小文件）。
- 未卸载应用、未清用户数据（仅本测试轮次内 `pm clear` 用于 B 轮干净首启验证，属验证步骤，且应用数据是本次测试产生的）。
- 每轮结束都 `am force-stop`（游戏 15~20s 观察窗内截标题界面后立即杀进程）。

## 8. 遗留风险 / 注意事项

- **R1 16KB page size 系统提示**：该 AVD 为 16KB 页大小，本包 arm64 原生库未 16KB 对齐（RELRO），首次启动/`pm clear` 后会弹系统「Android App Compatibility」提示，点 **Don't Show Again** 后进入 page-size compatible mode 正常跑。**不是 APK 缺陷**（原始 1.57.0 包同样如此，非我们的重打包引入）；4KB 页大小真机/模拟器不会出现。v2/v3 复测中已点掉，之后启动不再弹。
- **R2 version 标记已修正（v3）**：v1/v2 用 zip 内滞后的 `lwlocal/version.txt`(v1.1-20261108) 做 marker；v3 构建新增 `assets/tlw_cn.version = v1.3-20261109b`，安装器优先用它，marker/UI 已显示 v1.3-20261109b，且设备上旧 marker 会自动触发一次「更新重装」（已实测）。zip 内 `data pack version.txt` 仍会在日志打印 v1.1-20261108，仅作数据包元数据，不再影响 marker。
- **R3 adb root 不可用**：内部 `/data/data/<pkg>` 无法由 shell 直接读取，故内部 `files/cache` 的 84 个 master 文件只能通过应用日志 `master=84` + 总量守恒 `445234854` 间接确认；外部 345 个 `__data` 已逐项数量/字节和/抽样哈希验证。调试钩子已验证走**外部**路径 `/sdcard/Android/data/<pkg>/files/tlw_cn/`（shell 可写），内部钩子在本模拟器上无法创建。
- **R4 模拟器自身噪音**：`android.hardware.uwb` HAL 每 ~5s SIGABRT（系统进程，与应用无关）；偶发 `EGL_BAD_ACCESS` 警告（不致命）。判定只看应用 pid 的 FATAL/存活。
- **R5 空间**：本包安装 + 445MB 解包后 /data 剩 2.5G（v3 重装时再次解包）；解包耗时 4~9s，无需 skip 钩子做常规验证。

## 9. 关键证据文件（work\device\evidence\）

| 轮次 | 截图 | logcat |
|---|---|---|
| 基线 | `baseline-title.png`、`baseline-launch.png` | `baseline-*.txt` |
| stub | `cnfps-title.png`、`cnfps-launch-t8s.png` | `cnfps-logcat-app.txt` |
| v1 最终包 | `final-cn-title.png`、`progress-shot-1.png`(67%)、`progress-shot-2.png`(100%) | `final-cn-logcat*.txt` |
| **v2 A** | `v2-A-quickpath-title.png` | `v2-A-logcat.txt` / `v2-A-logcat-tlwcn.txt` |
| **v2 B** | `v2-B-progress-1.png`（65%）、`v2-B-progress-2.png`、`v2-B-done.png`（完成+钩子提示） | `v2-B-logcat.txt` / `v2-B-logcat-tlwcn.txt` |
| **v2 C** | `v2-C-title.png` | `v2-C-logcat.txt` / `v2-C-logcat-tlwcn.txt` |
| **v3 启动1（更新重装）** | `v3-launch1-progress-1.png`（更新提示 19%）、`v3-launch1-progress-2.png`、`v3-launch1-loading.png`、`v3-launch1-title.png` | `v3-launch1-logcat.txt` / `v3-launch1-logcat-tlwcn.txt` |
| **v3 启动2（快路径）** | `v3-launch2-title.png` | `v3-launch2-logcat.txt` / `v3-launch2-logcat-tlwcn.txt` |
| 校验 | `unpack-verify.txt`、`unpack-expected-inventory.txt`、`v2-final-verify.txt` | `v2-install.log`、`v3-install.log` |
