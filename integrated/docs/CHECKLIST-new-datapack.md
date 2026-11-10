# 换数据包 / 换版本时的检查清单

> 打包一般由 AI 执行，不用人手动记数字。这份清单是给「AI 接手时」看的，
> 也是你自己复核用的。**核心只有一条：`EXPECTED_ENTRIES` / `EXPECTED_BYTES` 必须跟新数据包对上。**

---

## 一、每次换 `lwlocal.zip` 必做的三件事

### 1. 算新的两个常量

```powershell
python -c "import zipfile; z=zipfile.ZipFile('assets\lwlocal-vX.Y.zip'); n=[i for i in z.infolist() if not i.filename.endswith('/')]; print('entries=',len(n)); print('bytes=',sum(i.file_size for i in n))"
```

口径：**所有非目录条目全算**（包括 `lwlocal/version.txt`）。
当前 ci2 的值：`761` / `438036025`（对应 v1.4）。

### 2. 改源码

`src\tlw\cn\CnSetupActivity.java` 第 111-112 行附近：

```java
private static final int EXPECTED_ENTRIES = 761;
private static final long EXPECTED_BYTES = 438036025L;
```

### 3. 检查数据包结构有没有变

```powershell
python -c "import zipfile,collections; z=zipfile.ZipFile('assets\lwlocal-vX.Y.zip'); n=z.namelist(); print(collections.Counter(x.split('/')[0] for x in n)); print('master',len([x for x in n if x.startswith('lwlocal/master/')])); print('bundles',len([x for x in n if x.startswith('lwlocal/bundles/')]))"
```

要确认：

| 检查项 | v1.4 的值 | 变了会怎样 |
|---|---|---|
| 顶层只有 `lwlocal/` | ✅ | 出现别的目录 → 会被 `ignore unexpected entry` 跳过，不报错但少装 |
| `master/` 下是平铺文件 | ✅ 70 个 | 出现子目录 → `isSafeSegment` 会跳过 |
| `bundles/` 是 `<A>/<B>/__data` 三层 | ✅ 345 组 | 层数变了 → 全部被当 malformed 跳过 |
| 有没有自带 `__info` | ✅ 345 个（会跳过不落盘） | 没有也能跑，安装器自己生成 |
| `lwlocal/version.txt` 存在 | ✅ `v1.4-20261110b` | 不存在会走 `probeVersion` 兜底 |

## 二、换游戏版本（base.apk / split）必做的

1. 换 `apk\<ver>\base.apk` + `split_arm64.apk`
2. **确认启动 Activity 名**：
   ```powershell
   & "D:\...\aapt2.exe" dump badging apk\<ver>\base.apk | Select-String "launchable-activity"
   ```
   不是 `com.google.firebase.MessagingUnityPlayerActivity` 就传 `-OldActivity`
3. **确认 `targetFrameRate` 偏移还有效**：
   ```powershell
   python tools\check_offset.py apk\<ver>\split_arm64.apk
   ```
   输出 `value=-1 OK` 才算过；不是的话要更新 `UnityFps.OFF_TFR_KNOWN`
4. **`KNOWN_VER` 加新版本号**（`src\tlw\fps\UnityFps.java`）
   不加也能用（会走 `scan()` 现场找），但每次启动多几百毫秒

## 三、出包命令

```powershell
cd tlw\TLW-cn-fps-project
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-local.ps1 `
  -BaseApk apk\1580\base.apk `
  -SplitApk apk\1580\split_arm64.apk `
  -CnZip assets\lwlocal-v1.4.zip `
  -CnVersion "v1.4-20261110b+ci2" `
  -Out out\TLW-global-1.58.0-cn-fps-v14c2.apk
```

## 四、出包后必须验的

```powershell
$apk = "out\TLW-global-1.58.0-cn-fps-v14c2.apk"
$bt  = "C:\Users\Quan\Documents\deepseek-harness\default-workspace\tlw\lwmod-adapt\sdk\bt\android-14"

# 1) 包名 / versionCode / launcher / ABI
& "$bt\aapt2.exe" dump badging $apk | Select-String "^package:|^launchable-activity:|^native-code:"

# 2) 签名
& "$bt\apksigner.bat" verify --print-certs $apk | Select-Object -First 2

# 3) 对齐
& "$bt\zipalign.exe" -c -p 4 $apk ; "align=$LASTEXITCODE"

# 4) 内置数据包是不是新的那份（大小要对上）
python -c "import zipfile; z=zipfile.ZipFile(r'$apk'); i=z.getinfo('assets/lwlocal.zip'); print('lwlocal',i.file_size,'stored' if i.compress_type==0 else 'DEFLATED'); print('version',z.read('assets/tlw_cn.version'))"
```

## 五、上机后必须看的三条日志

```
TlwCn : extract done: entries=… seen=… master=… bundles=… cacheInfo=… packagedInfo=… prunedMaster=… prunedBundles=… version=…
TlwCn : game activity started: …
TlwFps: attach base=0x… views=… tfr=0x… writable=true via 内置/缓存/扫描 <ver>
```

- `seen` 应该 **≥ EXPECTED_ENTRIES**
- `version` 应该等于 `-CnVersion` 传的值
- `via` 最好是 `内置 <ver>` 或 `缓存 <ver>`；如果是 `扫描` 说明 `KNOWN_VER` 没加，如果是 `回退` 说明偏移失效

## 六、踩过的坑（别再踩）

| 坑 | 现象 | 解法 |
|---|---|---|
| 忘了改 `EXPECTED_ENTRIES` | 安装器抛「数据包不完整」 | 按第一节算 |
| `EXPECTED_ENTRIES` 改小了 | 进度条超过 100% | 同上 |
| 数据包 master 数量变少但没清旧表 | **商店/任务面板黑屏**（NullReferenceException） | ci2 起有 `pruneStale` 自动清；更早版本要手动删 |
| PS 5.1 下跑 `build-cn.ps1` 原件 | `NameError: name 'wb' is not defined` | 用 `build-local.ps1` 包装（它会替换那一行） |
| 本机没有标准 SDK 根 | `Android SDK not found` | `build-local.ps1` 会用 `..\lwmod-adapt\sdk` 拼临时根 |
| `build-local.ps1` 存成无 BOM 的 UTF-8 | 脚本里中文变乱码、解析报错 | 存成 **UTF-8 with BOM** |
