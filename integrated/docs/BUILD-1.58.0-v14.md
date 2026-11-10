# 1.58.0 + 汉化 v1.4 出包记录（2026-11-10 晚）

> 上游 <https://github.com/xiake595/lostword-cn-patch> 发了 **v1.4（适配 1.58.0）**，按你的要求**只本地出包、没有推任何东西到 GitHub**。
> 产物：`out\TLW-global-1.58.0-cn-fps-v14.apk`（564.7 MB）

---

## 一、产物

| 文件 | 大小 | SHA-256 |
|---|---|---|
| `out\TLW-global-1.58.0-cn-fps-v14.apk` | 592,182,744 (564.7 MB) | `14012C232C91EEFF7C91D3BB821FB3A5115683F309D02149E380F2F097776646` |

- 游戏：国际服 **1.58.0 / versionCode 7016**
- 汉化数据：**v1.4-20261110b**（`lwlocal.zip` 378,134,402 B，SHA-256 `9B6F1C90…C7E2`，与 Release 声明一致）
- 标记：`assets/tlw_cn.version = v1.4-20261110b+ci1`
- 签名 `CN=TLW FPS`、包名/versionCode 官方原值、`zipalign -c -p 4` 通过
- **同签名**，可以从现在装的包直接覆盖升级，存档保留

## 二、v1.4 数据包跟 v1.3 的差别（我逐项比过）

| 项 | v1.3 | v1.4 |
|---|---|---|
| 条目数 | 430 | **761** |
| 资源包 `__data` | 345 | 345（目录名完全相同的 345 个 A 目录） |
| 资源包 `__info` | ❌ 没有（靠安装器补） | ✅ **自带 345 个** |
| 主数据表 | 84（含 `manifest.json`） | **70**（少 14 张：任务 `MissionMaster`、交换所相关等） |
| 未压缩总量 | 445,234,868 B | 438,036,025 B |
| zip 内 version.txt | `v1.1-20261108`（滞后） | **`v1.4-20261110b`**（终于对了） |
| 345 个 bundle 内容 | — | **149 个与 v1.3 完全相同，196 个已重做** |
| 70 张主表 | — | 只有 7 张与 v1.3 逐字节相同，63 张重做（按行替换，表结构不变） |

Release 说明里讲得很清楚：主表从「整表替换」改成「按行 ID 只换文本单元格」，因为 1.58 的 `MissionMaster`
从 5,622,032 B 变成 5,800,992 B，整表覆盖会让字段错位（就是 1.58 更新当天那个「课题名 / ×123456」事故）。
任务和交换所这一版**故意不汉化**，换稳定。

## 三、安装器改了 4 处（`src/tlw/cn/CnSetupActivity.java`）

1. `EXPECTED_ENTRIES` 430 → **761**，`EXPECTED_BYTES` 445,234,868 → **438,036,025**
   （不这样改，安装器会在「条目不完整」检查处直接抛异常，因为 v1.4 有 761 个条目）
2. 新增 `__info` 分支：数据包自带的 345 个 `__info` **读掉但不落盘**
   —— 包里那份的 mtime 是打包时的固定值 `1794314264`，跟刚写出的 `__data` 对不上；
   仍然由安装器按 `__data` 真实 mtime 重新生成，保证 Unity 认
3. 新增 `skipEntry()`：ZipInputStream 必须把当前条目读完才能走下一个，不能直接 continue
4. 日志加 `packagedInfo=345`，界面文案 `445 MB` → `418 MB`

## 四、MuMu 实测（`127.0.0.1:7555`，Android 12，arm64 翻译）

```
22:29:19.369 I TlwCn : probeAsset: zipPresent=true version=v1.4-20261110b+ci1
22:29:19.377 I TlwCn : extract start: …
22:29:19.388 I TlwCn : data pack version.txt = [v1.4-20261110b]
22:29:24.678 I TlwCn : extract done: entries=416 seen=761 master=70 bundles=345
                       cacheInfo=345 packagedInfo=345 bytes=438028075 elapsedMs=5301
                       version=v1.4-20261110b+ci1
22:29:24.757 I TlwCn : game activity started: …MessagingUnityPlayerActivity
22:29:25.152 I TlwFps : attach base=0x30b8000 views=1 tfr=0x199cc54 writable=true via 缓存 1.58.0
```

- 安装 `adb install -r` 25.3 s Success（从 1.58.0 的旧包直接覆盖）
- 解包 **5.3 秒**，761 个条目全部读到（`seen=761`），无 FATAL EXCEPTION
- 外部缓存：`__data` 4893 / `__info` 4894，其中 **345 个是安装器写的**
- `files/cache` 1250 个文件，**70 张表全部在 22:29 被 v1.4 覆盖写入**
- 进游戏 → 下载提示 → 下载完成 → 大厅，**安装器写的 345 个 `__data` 一个都没被游戏清掉**（22:30 后新下载 0 个）
- 界面（截图 `docs\screenshots-1580-v14\`）：
  - 顶栏 `好友 / 图鉴 / 道具 / 邮箱 / 公告` ✅
  - 底部 `商店 / 伙伴 / 绘卷 / 设施 / 任务 / 祈愿` ✅
  - 伙伴一览：`绵月丰姬 / 魂魄妖梦 / 芙兰朵露·斯卡雷特 / 博丽灵梦 / 依神紫苑 / 车东风谷早苗 / 铃仙·优昙华 / 雾雨魔理沙 / 泷木华扇 / 土造魅须丸 / 生驹润美` ✅ **角色名全中文**
  - 剧情对话：`芙兰朵露·斯卡雷特：不知道尤魔最近为什么老躲着我……咦？等等，你刚才在偷看我？你最差劲了。` ✅ **台词中文**
  - 卡片上的 `ATK / SUPP / DEST / TECH / HEAL` 和 `Exchange / Errand` 仍是英文 —— **上游已知项，不是包的问题**
  - 任务/交换所保持英文 —— **v1.4 故意的**（见第二节）

## 五、已知限制（v1.4 自带）

1. 任务（课题）和交换所/商店**故意保持英文**，为的是不再触发 1.58 的字段错位事故
2. 1.58 新增的 `another`、`event78` 两个剧情篇章还没翻
3. 卡片职业标记 `ATK/SUPP/SPD`、`Exchange`/`Errand` 按钮图是图片资源，上游未替换
4. 游戏再更新大版本，bundle hash 会再变，届时还要等上游适配

## 六、想回退

同签名可以直接覆盖回旧包（versionCode 相同，不用卸载）：

```powershell
adb install -r tlw\TLW-cn-fps-project\out\TLW-global-1.58.0-cn-fps.apk      # 回到 v1.3 数据（半中文）
adb install -r tlw\TLW-cn-fps-project\out\TLW-global-1.58.0-fps.apk         # 回到纯解帧
```

## 七、重新出包

```powershell
cd tlw\TLW-cn-fps-project
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-local.ps1 `
  -BaseApk apk\1580\base.apk -SplitApk apk\1580\split_arm64.apk `
  -CnZip assets\lwlocal-v1.4.zip -CnVersion "v1.4-20261110b+ci1" `
  -Out out\TLW-global-1.58.0-cn-fps-v14.apk
```
