> 历史技术记录：本机路径、密钥和成品位置已调整；当前构建方式见 [README](../../README.md)。

# 接手说明：以后换新版本怎么出包

这份文件是给"未来的我"和"你自己"看的。会话不会跨次记住，**能记住的是这个目录里
的东西**——所以关键信息全写在这里，照着做就能出包。

---

## 〇、现在有四份成品

| 包 | 包名 | authority | 说明 |
|---|---|---|---|
| `out\TLW-global-1.57.0-fps.apk` | `jp.goodsmile.touhoulostwordglobal_android` | `tlw.fps.boot` | 国际服，覆盖官方 |
| `out\TLW-global-1.57.0-fps-coexist.apk` | `jp.goodsmile.touhoulostwordglobal_andr0id` | `tlw.fps.boot.coexist` | 国际服，与官方并存 |
| `out\TLW-jp-1.71.1-fps.apk` | `jp.goodsmile.touhoulostword_android` | `tlw.fps.boot.jp` | **日服**，覆盖官方 |
| `out\TLW-jp-1.71.1-fps-coexist.apk` | `jp.goodsmile.touhoulostword_andr0id` | `tlw.fps.boot.jpcoexist` | **日服共存版** |

日服覆盖版：

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 `
  -BaseApk "apk\jp\base.apk" -SplitApk "apk\jp\split_arm64.apk" `
  -Icon "assets\tlw_icon_jp.png" `
  -Authority "tlw.fps.boot.jp" `
  -Out "out\TLW-jp-1.71.1-fps.apk"
```

日服共存版（**用脚本，别在命令行传日文参数**）：

```powershell
powershell -ExecutionPolicy Bypass -File build-jp-coexist.ps1
```

> 为什么单独一个 .ps1：`-Label` / `-OldLabel` 是日文，PowerShell 5.1 从命令行读
> 非 ASCII 参数会按系统代码页解码，很容易变乱码。写进 `.ps1`（UTF-8 **with BOM**）
> 就没事。改日服包名/应用名的时候记得**同时**改这个文件和 `build.ps1` 的默认值。

四个包 authority 各不相同，所以能同机共存。日服 1.71.1 实测：
`attach ... tfr=0x199cc54 writable=true via 内置 1.71.1`，和国际服同一个 Unity
构建，偏移一致。

日服的共存改名同样是等长替换：包名 35 字符（`android` → `andr0id`），
应用名 24 字节（`東方ロストワード` → `東方ロストＦＰＳ`，全角字母也是 3 字节）。

---

## 一、一句话流程

换掉 `apk\base.apk` 和 `apk\split_arm64.apk`，然后跑一条命令。

### 覆盖版（顶掉官方客户端）

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 `
  -Out "out\TLW-global-新版本号-fps.apk"
```

### 共存版（和官方客户端并存）

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 `
  -Pkg "jp.goodsmile.touhoulostwordglobal_andr0id" `
  -Label "TLW FPS Unlock!" `
  -Authority "tlw.fps.boot.coexist" `
  -Out "out\TLW-global-新版本号-fps-coexist.apk"
```

两条命令都能在 1~2 分钟内出包（205 MB）。

---

## 二、升级能直接覆盖安装的四个前提

这四条只要不变，老用户 `adb install -r` 或者在手机上直接点新 APK 就能原地升级，
**存档、设置、悬浮窗位置全部保留**：

| # | 不能变的东西 | 在哪 |
|---|---|---|
| 1 | 签名用的 keystore 和密码 | `tlw-release.jks`，密码在 `build.ps1` 第 37 行 `$pass` |
| 2 | 覆盖版的包名 `jp.goodsmile.touhoulostwordglobal_android` | 不传 `-Pkg` 就是它 |
| 3 | 共存版的包名 `jp.goodsmile.touhoulostwordglobal_andr0id` + authority `tlw.fps.boot.coexist` | 上面那条命令 |
| 4 | versionCode 只增不减 | **自动的**：manifest 从 `apk\base.apk` 里抽，版本号跟着官方走 |

> 注意：覆盖版和共存版是**两个不同的包**，互相之间不能"升级"，只能各自升级。
> 想让用户从覆盖版切到共存版，等于换一个 App（数据不迁移）。

---

## 三、出包前自检（30 秒）

```powershell
# 0) 偏移对不对（不用装、不用启动，直接读 split 里的 libunity.so）
python tools\check_offset.py apk\jp\split_arm64.apk     # 要打印 value=-1 ... OK
python tools\check_offset.py apk\split_arm64.apk

# 1) 包名 / 应用名 / ABI / versionCode 对不对
sdk\bt\android-14\aapt2.exe dump badging out\TLW-global-xxx.apk |
  Select-String "^package:|^application-label:|^native-code:"

# 2) 签名是不是那把老 key（DN 必须是 CN=TLW FPS）
sdk\bt\android-14\apksigner.bat verify --print-certs out\TLW-global-xxx.apk

# 3) 装上，看注入日志
adb install -r out\TLW-global-xxx.apk
adb logcat -s TlwFps:*        # 要能看到 attach ... writable=true via 内置/扫描 x.y.z
```

第 3 步的关键一行是：

```
TlwFps : attach base=0x... tfr=0x199cc54 writable=true via 内置 1.57.0
```

`via` 后面是 `内置 <版本>` / `扫描 <版本>` 都算成功；如果是 `回退 <版本>`，
说明新版本没扫到偏移，这包只显示数字、改不了帧率，得重新找地址。

---

## 四、新版本可能变的四样东西

| 会变的 | 表现 | 处理 |
|---|---|---|
| `versionCode` / `versionName` | 无感 | 自动从 base.apk 抽 |
| 启动 Activity 名字 | 构建直接报错：`hardwareAccelerated did not land on any activity` | `-Activity com.xxx.NewActivity`（用 `aapt dump badging` 查 `launchable-activity`） |
| `libunity.so` 里 `targetFrameRate` 的偏移 | 面板状态行显示「扫描 1.x.y」 | 不用管，运行时自动扫；扫不到才要人肉找 |
| 包名本身（官方换发行商） | 构建报错 `'<老包名>' not found` | `-OldPkg <新包名>`，共存版的 `-Pkg` 长度要跟着变成同长度 |

---

## 五、已经踩过的坑（别再踩一遍）

1. **共存版包名不能只差大小写**。MuMu/雷电的 `/sdcard` 挂在 NTFS 上（大小写不敏感），
   `...Global_...` 和 `...global_...` 会落到同一个 inode，新包拿到官方目录但 uid 不同，
   游戏报 `Not enough storage space to install required resources`。用 `andr0id`（o→0）。
2. **共存版必须换 provider authority**，否则 `INSTALL_FAILED_CONFLICTING_PROVIDER`。
3. **改包名只能等长替换**（41 字符）。多一个字都不行——`clone.py` 会直接拒绝，
   不会产出坏包。原因是 `resources.arsc` 不走重编码。
4. **`-Label` 也必须等长**（`Touhou LostWord` = 15 字节），UTF-8。
5. **别在触摸分发里同步 `removeViewImmediate`**，也别让面板窗口长期可获焦点——
   见 `docs\技术说明.md` 里那两节，都是实测崩过的。
6. **`build.ps1` 用 `Select-Object -First N` 截断输出会把构建打断**，
   要存日志请用 `*> build\log.txt` 再读文件。

---

## 六、目录里什么是命根子

```
tlw-release.jks        签名。丢了 = 老用户必须卸载重装（存档没了）
src\tlw\fps\*.java     全部逻辑
tools\axml.py         二进制 manifest 编辑
tools\repack.py       原样重打包
tools\clone.py        共存版的等长改名
build.ps1             一键构建（含上面所有步骤）
assets\tlw_icon.png    图标
r8.jar  sdk\           构建依赖
apk\                   每次换版本要替换的两个原始包
```

`build\` / `extract\` / `probe\` / 根目录的 png 都是可删的中间产物。

---

## 七、怎么拿到新版本的 base + split

在**没装改版**的设备（或另一台模拟器）上把游戏更到最新，然后：

```bash
adb shell pm path jp.goodsmile.touhoulostwordglobal_android
# package:/data/app/.../base.apk
# package:/data/app/.../split_config.arm64_v8a.apk
adb pull /data/app/.../base.apk                 apk/base.apk
adb pull /data/app/.../split_config.arm64_v8a.apk apk/split_arm64.apk
```

拿到的是整合包（universal，so 已经在 base 里）也能用：`-SplitApk` 传同一个文件，
`repack.py` 会去重。
