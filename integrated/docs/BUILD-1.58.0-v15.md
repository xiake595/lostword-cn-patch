# 1.58.0 + 汉化 v1.5（完整版）合并出包记录（共存版）

> 时间：2026-11-14 17:40。上游：仓库 `main`（`51009d5 feat(cn): v1.5 data pack — 431 bundles + 79 masters + 271 story bundles`）+ Release `v1.5` 数据包。
> 产物：`out\TLW-global-1.58.0-cn-fps-coexist.apk`，**906,055,262 B（864.1 MB）**，
> SHA-256 `564AB1A1A179747FE84DB352B534256E6691EFD42972F3976C19875BECDA5AE550`。

## 一、v1.5 数据来源与内容

| 项 | 值 |
|---|---|
| 版本 / 目标游戏 | `1.5` / 国际服 1.58.0（versionCode 7016） |
| 数据包 | Release 附件 `tlw-payload-v1.5.zip`：690,573,614 B，SHA-256 `4164d936c79d781e9b29d459ee181d4de07ca81b9dfb783fa2391a43153c013f` |
| 内容 | 主表 **79** 张（AES-128-CBC，49,872,912 B）+ 资源包 **431** 个（628,235,654 B）+ 剧情包 **271** 个（100,716,526 B） |
| 解包总量 | **778,825,092 B（约 743 MiB）** |
| 与 v1.4 差异 | 主表 70 → 79（补回任务/商店等 11 张）；资源包 345 → 431；新增 271 个剧情包（主线/活动/角色剧情） |
| 明确排除 | `UnitMaster`（`4c6c82a379efc3a6900021cb359ab194`）：长度变化会让「伙伴」界面黑屏 |

> 说明：用户提供的 `东方lost word汉化插件v1.5.7z`（516,492,494 B）只含 431 资源包 + 79 主表，**缺 271 个剧情包**，与仓库 v1.5 不一致。本次按仓库 `main` + Release `tlw-payload-v1.5.zip` 合并（sha256 已核对）。

## 二、合并到整合 APK 做了什么

1. **payload → `assets/lwlocal.zip`**：
   - `payload/master/*` → `lwlocal/master/<hash>`（79）
   - `payload/uc/*.bundle`（431）+ `payload/story/*.bundle`（271）→ `lwlocal/bundles/<A>/<B>/__data`（702）
   - `lwlocal/version.txt = v1.5-20261114`
   - 共 **782 条目**，zip **691,904,867 B**（条目 deflate），解包 778,825,092 B；
     sha256 `72219c050b0dcb8f358d0ad999b73a61c0bc048ef3e2f1d8114d3acdd9ad87c5`。
2. **安装器常量**：`EXPECTED_ENTRIES=782`、`EXPECTED_BYTES=778,825,092`；界面文案改 743 MB；
   数据标记 `v1.5-20261114+ci2`（含剧情包，与只含 431 包的 ci1 区分），`assets/tlw_cn.game=1.58.0` 不变。
3. **清理旧表改为「按大小校验」**（针对 11-11 诊断出的「修复后 59.4MB 主数据重下覆盖汉化」）：
   - `installed.list` 新格式 `name<TAB>写入大小`；下次升级只删「大小仍等于当时写入值」的旧表；
     旧格式（只有名字）不删——宁可留旧文件，也不删掉游戏后来下载的官方版本。
   - `assets/tlw_cn_legacy.txt` 缩到 5 条 `name<TAB>旧版大小`（`6d7c73da…`、`6f86f319…`、`manifest.json`、
     `d48fdca6…`、`91cd32ae…`），同样按大小校验才删；**不含 UnitMaster**。
   - 资源包仍按 `installed.bundles` 清旧 key（v1.4→v1.5 首次升级清理 286 个；ci2 的 431 资源包是 702 key 子集，无需再清）。
4. 其余（双 `__info` 写入、「缓存修复」、「还原官方缓存」、版本校验、解包失败「跳过汉化」）沿用 ci3。

## 三、静态校验

- `aapt2 dump badging`：`package name='jp.goodsmile.touhoulostwordglobal_andr0id' versionCode='7016'
  versionName='1.58.0'`、`application-label:'TLW CN FPS Mod!'`、`launchable-activity: tlw.cn.CnSetupActivity`、
  `native-code: arm64-v8a`。
- `apksigner verify`（v1+v2+v3，`CN=TLW FPS`）、`zipalign -c -p 4` 通过；APK 共 4,721 条目。
- APK 内：`assets/lwlocal.zip` 691,904,867 B（782 条目）、`assets/tlw_cn.version = v1.5-20261114+ci2`、
  `assets/tlw_cn.game = 1.58.0`、`assets/tlw_cn_legacy.txt` 175 B。

## 四、真机冒烟（HyperOS `dd3e0d04`，Android 16）

`adb install -r` 17.1 秒 Success（同包名同签名，数据保留）。外部调试钩子 `no_autolaunch` 只跑安装器：

```
extract start: filesDir=/data/user/0/jp.goodsmile.touhoulostwordglobal_andr0id/files
targets: cache=…/files/cache bundleRoot=…/files/UnityCache/Shared
data pack version.txt = [v1.5-20261114]
marker written: …/tlw_cn/installed.txt = v1.5-20261114+ci2
extract done: entries=782 seen=782 master=79 bundles=702 cacheInfo=702 packagedInfo=0
              prunedLegacy=0 prunedMaster=0 prunedBundles=0 bytes=778825092
              elapsedMs=15305 version=v1.5-20261114+ci2
no_autolaunch hook: stay on done screen
```

- 解包 15.3 秒；UnityCache 5,294 个 `__data` / 5,295 个 `__info`（1.8 GB，含新增 271 个剧情包）。
- 测试后已删除 `no_autolaunch` / `diag_dump` 钩子；未做登录与游戏内验证（留给使用者）。
- 上一轮「59.4MB 主数据重下」修复点：v1.5 已包含任务/商店表（不再因缺文件触发整包重下），
  清理只删「大小仍等于我们写入值」的文件；实际进游戏是否还触发更新仍需验证。

## 五、已知限制（v1.5 上游）

- `UnitMaster` 不包含 → 角色名英文；「伙伴」界面 `Friend List` / `一健保护` / `告别` 等仍英文。
- 任务卡片背景为国际服原生设计，无法替换。
- 1.58 新增 `another` / `event78` 剧情篇章仍未翻译。

## 六、复现构建

```powershell
# 输入：apk/1580/{base.apk,split_arm64.apk}、assets/lwlocal.zip（v1.5 完整版，782 条目）、
#       assets/tlw_cn_legacy.txt、tlw-release.jks、r8.jar
$env:TLW_KEYSTORE_PASSWORD = '...'
.\build-cn.ps1 -Pkg "jp.goodsmile.touhoulostwordglobal_andr0id" `
  -Label "TLW CN FPS Mod!" -Authority "tlw.fps.cn.coexist" `
  -Out "out\TLW-global-1.58.0-cn-fps-coexist.apk"
```
