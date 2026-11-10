> 历史技术记录：本机路径、密钥和成品位置已调整；当前构建方式见 [README](../../README.md)。

# 东方归言录（国际服）内置帧率悬浮窗

> 换新版本要出包？直接看 **[HANDOVER.md](HANDOVER.md)** —— 一条命令、四个不能改的参数、出包前自检清单。

装进 APK 里的解帧小窗：打开游戏就有，**不用 root、不用 adb、不装模块**。

- 成品（覆盖版，顶掉官方客户端）：`out/TLW-global-1.57.0-fps.apk`
- 成品（共存版，和官方客户端并存）：`out/TLW-global-1.57.0-fps-coexist.apk`
- 成品（**日服**，顶掉官方客户端）：`out/TLW-jp-1.71.1-fps.apk`
- 成品（**日服共存版**）：`out/TLW-jp-1.71.1-fps-coexist.apk`

四个都是 200 MB 左右的独立单包，arm64，Android 7.0+。

---

## 零、它挂在哪个窗口上

| 方式 | 什么时候用 | 拖动手感 | 代价 |
|---|---|---|---|
| **系统悬浮窗**（默认） | 已授予「显示在其他应用上层」 | 窗口独立 GPU surface，移动由合成器完成 | 首次要手动授权一次 |
| 游戏内视图 | 没授权时的兜底 | 走 CPU 渲染，会顿 | 无需任何权限 |

为什么默认走系统悬浮窗：这个游戏的 Unity Activity 在 manifest 里写死了
`android:hardwareAccelerated="false"`，往它 decorView 里加的任何东西都是软件渲染，
每帧要在 CPU 上重画；系统悬浮窗有自己的 surface，跟游戏渲染完全解耦，
而且它不属于游戏的视图树，**游戏更新不会影响它**。

面板状态行会显示当前用的是哪种（「系统悬浮窗」/「游戏内视图」）。

授权页只在第一次弹一次。授权后重启游戏即可切到系统悬浮窗。

---

## 一、它长什么样、怎么用

| 操作 | 结果 |
|---|---|
| 平时 | 屏幕上一小圆球，显示当前写入的帧率（`165` / `OFF`） |
| 按住拖动 | **屏幕内任意位置**都能放，松手记住坐标（重启还在那） |
| 轻点球 | 弹出面板：输入框 + 「应用」+ 「还原默认帧率」+ 「隐藏悬浮窗」 |
| 输入数字后点「应用」 | 立即写入（10~480 之间），状态行回显结果 |
| 点「还原默认帧率」 | 写回 `-1`（游戏原厂值），帧率回到游戏自己的默认上限 |
| 点「隐藏悬浮窗」 | 球收起来，原位留一个半透明小点 |
| 点那个小点 | 球回来 |
| **长按**那个小点 | 彻底关掉，本次游戏进程内不再出现，**下次启动才回来** |

### 换图标

球上的图可以换成任意 PNG。**把图片放到 `assets/tlw_icon.png` 然后重新构建**就行
（换别的文件名就用 `-Icon` 指过去）：

```powershell
copy 你的图.png assets\tlw_icon.png
powershell -ExecutionPolicy Bypass -File build.ps1
```

构建时会打印 `icon -> assets/tlw_icon.png (N bytes)`，装完 logcat 里有
`custom icon loaded 253x253` 就说明生效了。图片会被**裁成圆形**；用了自定义图之后
帧率数字自动变成半透明（白色 82%，底下只垫一层很淡的暗色描边），图还是主角，
数字又能辨认。删掉 `assets/tlw_icon.png` 再构建就回到默认的纯色圆球。

> 为什么放 `assets/` 而不是 `res/drawable/`：加 drawable 要重新编码
> `resources.arsc`，而这条流水线刻意不碰它（原样重打包才能保证装得上）。
> `assets/` 是纯文件，塞进去就行，零副作用。

### 拖动

球不是只能贴边——拖到屏幕正中间、上下左右任意位置都行。系统悬浮窗模式下，
拖动是**移动整个窗口**（`WindowManager.updateViewLayout`），由 SurfaceFlinger
在合成阶段完成，app 侧一次 measure/layout 都不跑。

两条约束：不会拖出屏幕（四个方向都夹死在屏幕内）；窗口尺寸变了也不会丢坐标
（旋转、键盘导致窗口变小，球只是临时被夹进可视区，存档不动）。

面板会跟着球走，并自动避让屏幕边缘：球在左半边就朝右展开，在右半边就朝左展开；
靠近底部就向上翻，保证整个面板永远完整可见。

![悬停球](docs/screenshots/01-badge.png)

面板本身：

![面板](docs/screenshots/02-panel.png)

### 输入框整块都能点

面板是**独立的系统窗口**，创建那一刻尺寸就是最终的 522×589；球是另一个
固定 130×130 的窗口，只移动、永不改尺寸。

这么拆是被坑出来的：半透明 overlay 的 `touchableRegion` 只在 `addView`
那一刻算一次，运行时 `updateViewLayout` 改尺寸只更新 frame、不更新可点区域，
表现就是「输入框只有左上角一小块能点」。两个窗口各自在 addView 时定好尺寸，
这个问题就不存在了——实测输入框的正中心、四个角、四条边共 7 个点，全部能唤起输入法。

### 打字时才会拿走焦点

面板窗口平时是「不可获焦点」的，游戏一直握着窗口焦点。只有你点输入框的那一刻，
面板窗口会重建一次成可获焦点版本把键盘叫起来；点「应用」「还原默认」或者关面板
立刻重建回去。

> 不这么做的话，点一次「应用」之后整个游戏就点不动了——系统会报
> `Input dispatching timed out (Application does not have a focused window)`，
> 也就是焦点没还给游戏。实测三条路径各走一遍，连点游戏 3 次，零 ANR。

隐藏后的小点：

![隐藏态](docs/screenshots/03-hidden-dot.png)

---

## 二、安装

### 方式 A：直接在设备里装

1. 把 `out/TLW-global-1.57.0-fps.apk` 拖进模拟器/手机
2. **必须先卸载原来的国际服**——签名不同，Android 不允许覆盖安装
3. 装完直接开游戏，不再弹任何权限框

> ⚠️ **`pm uninstall` 会连 `/data/data/<包名>` 一起删**（实测 Android 12/15 都是），
> 所以卸载前一定要拿好**引继码**，或者用下面带自动备份的脚本。

### 方式 B：adb（自动备份存档）

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Serial emulator-5558
```

脚本会 `su tar` 备份 `/data/data/<包名>` 到 `/sdcard`，卸载→安装→再灌回去并补
`chown` / `restorecon`。备份小于 1KB 会直接中止，不会让你白丢存档。
不想要存档就加 `-Wipe`。

> 换签名之后 `pm uninstall -k` 再装新包会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，
> 这是正常的——必须先 `pm uninstall`。

### 想和官方版并存？

看下面的「五之二」。

---

## 三、输入什么值才真能跑到

Unity 的 `Application.targetFrameRate` 不是自由值，它要跟显示器的 vsync 对齐，
真正跑出来的帧率是 **刷新率 ÷ N**。

| 输入 | 实际 | 说明 |
|---|---|---|
| 165 | 169 fps | 1/1 |
| 83  | 84 fps  | 1/2 |
| 55  | 56 fps  | 1/3 |
| 41  | 42 fps  | 1/4 |
| 33  | 33 fps  | 1/5 |
| 28  | 28 fps  | 1/6 |
| 100 | 85 fps  | 不是整数分之一，被量化到 1/2 |
| 默认（`-1`） | 游戏自己的默认上限，实测 ≈ 30 fps | 原厂值：不设帧率上限，由引擎决定 |

所以面板会**实时算给你看**：输入 100 时状态行写「当前 100 fps（实际 ≈ 83）」，
不会让你以为生效了。想精确控帧，就输 165 / 83 / 55 / 41 / 33 / 28 这些分频值
（60Hz 屏上是 60 / 30 / 20 / 15，240Hz 上是 240 / 120 / 80 / 60 / 48 / 40）。

> 想强行要 100fps 这种非整数分频？技术上要把 `eglSwapInterval` 强制成 0，
> 我试过（patch `libunity.so` 的 `bl eglSwapInterval` 调用点，把 `w1` 改成 `wzr`），
> 结果不是「能设 100」而是「彻底不锁帧、永远跑满 ~170」，输入框就失效了。
> 所以成品里**没有**动 `libunity.so`，保持原版字节不变。

---

## 四、账号与数据

- 重打包 = 换签名 = **不能覆盖安装**，必须先卸载原版。
- 卸载前一定拿好**引继码**（Menu → 引继），否则号就没了。
- **`pm uninstall` 会把 `/data/data/<包名>` 一起删掉**（Android 10+ 实测如此，
  不是"保留数据"的那种）。
- 帧率设置、悬浮球坐标存在 `/data/data/<包名>/shared_prefs/tlw_fps.xml`，
  和游戏存档同一个目录，一起没了。

---

## 五、游戏内热更新会不会把它冲掉

实测结论：**这个游戏的热更新只写外部存储，碰不到 APK。**

### 这个游戏的热更新只碰外部存储

```
/sdcard/Android/data/<包名>/files/il2cpp/Metadata/global-metadata.dat   13.7 MB
/sdcard/Android/data/<包名>/files/il2cpp/Resources/*.dat
/sdcard/Android/data/<包名>/files/il2cpp/unity.ver                      GUID，判断是否要重下
```

`libunity.so` / `libil2cpp.so` 在 **APK 内部**（`/data/app/.../lib/arm64/`），
热更新碰不到。

### 实测：删掉 metadata 强制重下

```
=== 强制刷新前 ===
global-metadata.dat  13709492   unity.ver: 093ea6c2-...
apk: /data/app/~~RHaquq.../base.apk

=== 删掉 il2cpp/ 整个目录，重启游戏 ===

=== 之后 ===
global-metadata.dat  13709492   <- 重新下载了
apk: /data/app/~~RHaquq.../base.apk   <- APK 路径完全没变
APK path UNCHANGED
悬浮窗照常挂上，帧率设置和坐标全部保留
```

### 为什么天然不受影响

| 我们的东西 | 放在哪 | 热更新会动吗 |
|---|---|---|
| `classes3.dex`（悬浮窗代码） | APK 内 | ❌ 不动 |
| `AndroidManifest.xml`（provider + 权限） | APK 内 | ❌ 不动 |
| `assets/tlw_icon.png`（图标） | APK 内 | ❌ 不动 |
| `libunity.so`（偏移来源） | APK 内 | ❌ 不动 |
| 帧率/坐标设置 | `/data/data/<包名>/shared_prefs/` | ❌ 不动 |

### 唯一会失效的情况：换 APK

| 情况 | 结果 |
|---|---|
| 游戏内热更新（下载资源/元数据） | ✅ 完全不受影响 |
| 应用商店更新 APK（同签名） | ❌ 被官方包覆盖，悬浮窗没了 |
| 手动装新版本 APK | ❌ 同上，要用新版本 base.apk 重新打包 |

也就是说：**只要不重新装 APK，它就一直活着。** 换版本的流程见 [HANDOVER.md](HANDOVER.md)。

---

## 五之二、共存版（和官方包同时装）

默认那份包会**顶掉官方客户端**（签名不同，必须卸载官方版才能装）。想留一个官方版
正常吃商店更新，就打一份改过包名的共存版：

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 `
  -Pkg "jp.goodsmile.touhoulostwordglobal_andr0id" `
  -Label "TLW FPS Unlock!" `
  -Authority "tlw.fps.boot.coexist" `
  -Out "out\TLW-global-1.57.0-fps-coexist.apk"
```

装完桌面上会出现两个图标：`TLW FPS Unlock!`（改版）和原版 `Touhou LostWord`，
互不干扰。官方版照常更新，改版等你有空了再重打包。

### 三条必须遵守的规则

| 规则 | 原因 |
|---|---|
| `-Pkg` 必须和原包名**一样长**（41 字符） | 走的是原地等长替换，一个字都不能多；长度不对直接报错，不会产出坏包 |
| 新包名不能只差大小写 | MuMu/雷电这类模拟器的 `/sdcard` 挂在 NTFS 上，**大小写不敏感**：`...Global_...` 会和 `...global_...` 落到同一个目录（实测 inode 相同），新包就会因为拿不到目录写权限而报「Not enough storage space」。所以用了 `andr0id`（o→0），真机和模拟器都安全 |
| `-Authority` 必须换一个 | provider 的 authority 全系统唯一，还用 `tlw.fps.boot` 会和之前那份包冲突（`INSTALL_FAILED_CONFLICTING_PROVIDER`） |

改的是两个文件里的 7 处字符串，全部**等长原地替换**，`resources.arsc` 体积不变
（211924 → 211924），所以也不违反"绝不重编码 arsc"这条铁律：

| 位置 | 命中 | 编码 |
|---|---|---|
| `AndroidManifest.xml` | 6 | UTF-16LE |
| `resources.arsc`（`ResTable_package.name`） | 1 | UTF-16LE |
| 应用名（`resources.arsc` 里的 label） | 1 | UTF-8 |

### 共存版的代价

- **存档是另一份**：包名不同 = 数据目录不同。想登同一个号要用引继码，
  而且同一账号不能两个客户端同时在线。
- **要重下一份资源**（实测官方版 `/sdcard/Android/data/<包名>` 约 870 MB）。
  非 root 没法共享——Android 10+ 的分区存储按包名隔离，
  `/sdcard/Android/data/<别的包名>` 和 `/data/data/<别的包名>` 都进不去，
  FUSE 也不支持软链接。root 机可以 `mount --bind` 把两份目录绑一起。
- 之后重建共存版时**包名和 authority 别改**，同一个 keystore 签的，
  `adb install -r` 直接覆盖升级，数据还在。

---

## 五之三、日服版

日服（`jp.goodsmile.touhoulostword_android`）和国际服是**两个不同的包**，各打各的：

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 `
  -BaseApk "apk\jp\base.apk" -SplitApk "apk\jp\split_arm64.apk" `
  -Icon "assets\tlw_icon_jp.png" `
  -Authority "tlw.fps.boot.jp" `
  -Out "out\TLW-jp-1.71.1-fps.apk"
```

和国际服的三处差别：换 `-BaseApk/-SplitApk`、换图标（`-Icon`）、换 provider
authority。三个包 authority 各不相同，所以可以同机共存。

日服 1.71.1 实测：`via 内置 1.71.1`，偏移和国际服同一个 `0x199cc54`，
出包前可以用 `python tools\check_offset.py apk\jp\split_arm64.apk` 离线确认。

> 日服要做共存版也能做，但记得把 `-OldPkg` 一起传：日服包名是
> `jp.goodsmile.touhoulostword_android`（35 字符，比国际服短），
> 新包名必须和**它**一样长，`clone.py` 是按你传进来的 `-OldPkg` 算长度的。

日服共存版直接跑现成的脚本（里面有日文参数，写进文件才不会被 PowerShell 的
代码页弄乱）：

```powershell
powershell -ExecutionPolicy Bypass -File build-jp-coexist.ps1
```

产出 `out/TLW-jp-1.71.1-fps-coexist.apk`：

| | 值 |
|---|---|
| 包名 | `jp.goodsmile.touhoulostword_andr0id`（35 字符，o→0） |
| 应用名 | `東方ロストＦＰＳ`（24 字节，和 `東方ロストワード` 等长） |
| authority | `tlw.fps.boot.jpcoexist` |
| 图标 | `assets/tlw_icon_jp.png` |

实测：四个包同机共存（国际服覆盖版/共存版、日服覆盖版/共存版），
日服共存版的 `map` 目录 inode 和在装版不同（`3932450` vs `3932294`），
资源是各存一份。

---

## 六、版本适配

| 版本 | 行为 |
|---|---|
| 国际服 1.57.0 / 日服 1.71.1 | 内置偏移 `0x199cc54`，秒开 |
| 其它版本 | 自动扫 `libunity.so`：`adrp/ldr/ret` 的 getter ∩ `adrp/str/b` 的 setter，取交集里值为 `-1`/`0` 的那个 |
| 扫描也失败 | 回退到内置偏移，面板会显示「回退 x.y.z」，此时档位可能无效 |

扫描结果按版本号缓存在 `shared_prefs/tlw_fps.xml`，同一版本第二次启动不再扫。

---

## 七、目录

```
out/            成品 APK
src/tlw/fps/    注入的 Java 源码
  TlwBoot.java    ContentProvider 入口（比 Application 更早跑）
  TlwCore.java    装配、守护线程、生命周期
  UnityFps.java   在 libunity.so 里找 targetFrameRate 并读写
  Mem.java        进程内内存访问（Unsafe + /proc/self/maps 校验）
  FpsOverlay.java 悬浮球 / 面板 / 隐藏点（纯代码构建，无 XML 资源）
tools/          构建工具
  axml.py         二进制 AndroidManifest 编辑器
  repack.py       原样重打包（保留压缩方式，不重编码 arsc）
  clone.py        共存版的等长改名
build.ps1       一键构建
install.ps1     一键安装（可选，带存档备份）
HANDOVER.md     换版本时先看这个
docs/           技术说明与截图
probe/          实测用的 adb 侧脚本（帧率测量、地址扫描等）
extract/        从 APK 里取出的 libunity.so（用于离线扫偏移）
apk/            原始 base.apk + arm64 split
sdk/            build-tools 34 + platform 35（构建用，不进 APK）
```

重新构建：

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

### 存档清单：留着这些，以后随时能再打一份

| 必须留 | 为什么 |
|---|---|
| `tlw-release.jks` | 签名。丢了就没法和旧包共存，只能卸载重装（存档清空） |
| `src/tlw/fps/*.java` | 全部逻辑 |
| `tools/*.py` | 改 manifest、原样重打包、共存版改名 |
| `build.ps1`、`install.ps1` | 一键构建 / 一键装 |
| `assets/tlw_icon.png` | 你换的那个图标 |
| `r8.jar`、`sdk/` | 构建依赖 |
| `docs/` | 技术说明 |

不用留的：`build/`（中间产物）、`extract/`（抽出来的 so）、`probe/`（调试脚本）、
根目录那些截图、以及 `apk/` 里的两个包——每次换版本都要换。

---

## 八、怎么做的（一句话版）

1. 用 apktool **只反编译 manifest**（`-r` 保留 arsc 原样），拿到二进制 AXML。
2. 用 `tools/axml.py` 直接改二进制：在 `<application>` 末尾插一个
   `<provider android:name="tlw.fps.TlwBoot" .../>`，再删掉
   `requiredSplitTypes` / `splitTypes`（否则单 APK 装不上）。
3. 把 `tlw.fps.*` 编译成 `classes3.dex` 塞进 APK。
4. 用 `tools/repack.py` 重打包：除 manifest / 新 dex 外，**每个条目按原压缩方式
   原样拷贝**（`resources.arsc`、`classes*.dex` 保持 STORED，否则 targetSdk 36
   会装不上），并从 arm64 split 里合并 `lib/arm64-v8a/*`，让成品是单 APK。
5. `zipalign -p 4` + `apksigner`（v1/v2/v3）。
6. 运行时：provider 在 `Application.onCreate` 之前就起来 → 起守护线程 →
   等 `libunity.so` 映射 → 找到 `targetFrameRate` 的地址 → 每秒校验并写回
   （游戏在关卡加载时会把值写回去，必须一直盯着）。

细节见 [docs/技术说明.md](docs/技术说明.md)。
