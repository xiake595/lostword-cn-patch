# 问题排查记录：汉化包被游戏清掉 / 角色名与 UI 回退英文

> 日期：2026-11-09　排查人：lead（模拟器 + 真机 dd3e0d04 / Redmi 23127PN0CC / Android 16）
> 结论：**不是汉化数据内容的问题，而是安装器少写了 Unity AssetBundle 缓存条目的 `__info` 元数据文件**。
> 已经修复并在此真机上验证：UI 标签、角色名、剧情全部恢复中文，且游戏没有重新下载/覆盖这些资源包。

## 一、现象

真机（全新安装整合包，登录后让游戏把资源下完整，约 10 分钟）：
- 帧率悬浮窗正常（120 FPS）；
- **角色名、UI 标签回到英文**（`Buddies / Journal / Items / Mail / Menu / Exchange / Errand / Explore / Shop …`）；
- 部分文本仍是中文（技能名、道具名、剧情台词、"与丰姬的羁绊"等）——这些来自主数据表（`files/cache`）。

## 二、取证

真机外部缓存（不需要 root）：

```
UnityCache/Shared/<A>/<B>/__data   4520 个
UnityCache/Shared/<A>/<B>/__info   4521 个（每个缓存条目一个，外加 Shared/__info）
```

对比汉化包里的 345 个 `<A>/<B>`：

| 项 | 数量 |
|---|---|
| 真机缓存里能找到的汉化包条目 | **76 / 345** |
| 其中 `__data` 大小与汉化包一致的 | **0 / 76**（全部被游戏下载的英文原包覆盖） |
| 真机缓存里完全找不到的汉化包条目 | **269 / 345**（被删） |

而安装器日志显示解包是完整的：

```
TlwCn: extract done: entries=430 seen=430 master=84 bundles=345 bytes=445234854 …
```

→ 345 个包都写进去了，但随后游戏初始化/下载资源时：没被引用的直接当垃圾清掉，被引用的重新下载英文原包覆盖。

关键差异在真机自己下载的条目：**每个目录里都有一对 `__data` + `__info`**，而我们的安装器只写了 `__data`。
真机 `__info` 是纯文本（23 字节）：

```
-1
1794211487
1
__data
```

`-1` = 未计算 CRC；第 2 行 = `__data` 的 mtime（epoch 秒）；`1` = 完成标记；最后一行 = 数据文件名。
`Shared/__info`（顶层，24 字节）格式为 `2147483647\n1\n<epoch>\n`，由游戏自己创建。

## 三、根因

Unity 的 AssetBundle 缓存按 `<cacheDir>/Shared/<hashA>/<hashB>/__data + __info` 组织。游戏的资源检查
（`AssetDownloader.IsCacheValid` → `Caching.IsVersionCached(name, hash)`）只会把**同时具有合法 `__info`
的目录**当成已缓存：

- 我们的条目只有 `__data` → `IsVersionCached` 返回 false；
- 游戏把这些目录当无效缓存清理；需要用到时重新下载英文包写到同一路径（76 个），其余（269 个）被删；
- 主数据表走的是 `File.Exists`，所以 `files/cache` 里的 84 个文件没受影响 → "部分中文仍正常"。

这也解释了为什么以前用 root 脚本 / LSPatch 模块"只写 `__data`"能用：那是在**已经下载过的设备**上覆盖，
`__info` 本来就在，游戏仍认为缓存有效；而整合包是首次安装、缓存为空，必须自己补 `__info`。

## 四、修复

`src/tlw/cn/CnSetupActivity.java` 解包每个 bundle 时，写完 `__data` 后同时写：

```java
// __info 内容（与真机游戏下载产生的格式逐字节一致）
-1\n<__data 的 mtime 秒>\n1\n__data\n
```

- 原子写（tmp → rename），失败抛异常（宁可让用户重试，也不留下"看着装完实际无效"的状态）；
- 数据版本标记从 `v1.3-20261109b` 升到 **`v1.3-20261109b+ci1`**，老安装升级后会自动重装一次；
- 日志新增 `cacheInfo=345` 便于验收。

## 五、真机验证（同一台 Redmi / Android 16）

安装新包（`adb install -r` 12 s，同签名升级保留数据）→ 启动：```
TlwCn: extract done: entries=430 seen=430 master=84 bundles=345 cacheInfo=345 bytes=445234854 elapsedMs=1500 version=v1.3-20261109b+ci1
TlwCn: game activity started: com.google.firebase.MessagingUnityPlayerActivity
```

- 缓存条目：`__data` 4520 → **4789**（+269，全部汉化包条目就位），`__info` 4521 → **4790**；
- 345 个汉化包在真机上**全部存在且大小与数据包完全一致**，mtime 全部 = 解包时间（17:57）；
- 游戏运行 1 分钟后复查：`-newermt 17:58` 的新 `__data` = **0 个**，目录数不变 → 没有被重新下载覆盖；
- 截图对比（`docs/screenshots/`）：
  - 修复前 `real-01-before-english.png`：`Buddies / Journal / Items / Mail / Menu / Exchange / Errand / Explore / Shop …`
  - 修复后 `real-02-after-chinese-home.png`：`好友 / 图鉴 / 道具 / 邮箱 / 公告 / 商店 / 伙伴 / 绘卷 / 设施 / 任务 / 祈愿 / 探索 / 初心者 …`，剧情台词中文
  - 修复后 `real-03-after-chinese-buddies.png`：伙伴一览角色名 `绵月丰姬 / 茨木华扇 / 古明地觉 / 雾雨魔理沙 / 芙兰朵露 …`

## 六、仍然英文的部分（上游汉化补丁的已知未完成项，不是本次 bug）

- 首页 `Exchange` / `Errand` 按钮图（sprite 图片，补丁 README 已列为未完成）；
- `Tower` / `Home` / `VS Spirits` 等卡片状态图标文字、活动横幅（服务器下发/图片）；
- 伙伴卡片左上角 `ATK/SUPP/SPD` 职业标记（图片）；
- 任务说明等少数主数据表字段（补丁 v1.3 发布说明中"仍待补"）。

## 七、验收命令（真机/模拟器都适用，不需 root）

```bash
BASE=/sdcard/Android/data/jp.goodsmile.touhoulostwordglobal_android/files/UnityCache/Shared
adb shell "find $BASE -name '__data' | wc -l"        # 期望 ≥ 345 + 游戏自己的缓存
adb shell "find $BASE -name '__info' | wc -l"        # 期望 ≈ __data 数量（每个条目都要有）
adb shell "ls $BASE | wc -l"
```

安装器侧：`logcat -s TlwCn` 应出现 `cacheInfo=345`，且集合大小与 `bundles=345` 相等。

## 八、兜底：悬浮窗「缓存修复」按钮

即使有了 __info，游戏以后仍可能因为**登录后首次下载资源 / 版本更新 / 清缓存**把内置汉化包冲掉
（或者用户拿到的是旧版本安装包）。为此在悬浮窗面板加了「缓存修复（汉化变英文时点这里）」：

1. `tlw.cn.CacheRepair.perform()`：删除 `files/tlw_cn/installed.txt`（以及误留的
   `skip_extract` / `no_autolaunch` 调试钩子）；
2. 用 `AlarmManager` + `PendingIntent` 在 1.5 s 后重新拉起 App（`FLAG_ACTIVITY_NEW_TASK
   | FLAG_ACTIVITY_CLEAR_TASK`），随后主动 `Process.killProcess` 结束当前进程 ——
   保证 Unity 在全新进程里重启，不会复用已加载的英文资源；
3. 重启后 `CnSetupActivity` 发现 marker 缺失且存在 `install.log` → 状态行显示
   「检测到汉化资源需要修复，正在重新安装…」，重新解包 445 MB（含 __info）后进游戏。

若系统拦截后台自启动（MIUI/HyperOS 等可能），用户手动点桌面图标打开游戏也一样会重新解包。
按钮文案与使用说明已同步到 `docs/使用说明.md`。

### 真机实测（Redmi 23127PN0CC / Android 16，2026-11-09 18:09）

```
18:09:05.062  TlwCn : cache repair: marker deleted, relaunch scheduled, killing process
（进程被杀，1.5s 后 AlarmManager 自动拉起新进程 pid 32024）
18:09:07.969  TlwCn : onCreate … skipExtract=false noAutolaunch=false
18:09:07.969  TlwCn : probeAsset: zipPresent=true version=v1.3-20261109b+ci1
18:09:07.979  TlwCn : extract start …
18:09:08.921  TlwCn : marker written: …/installed.txt = v1.3-20261109b+ci1
18:09:08.922  TlwCn : extract done: entries=430 seen=430 master=84 bundles=345
                      cacheInfo=345 bytes=445234854 elapsedMs=943 version=v1.3-20261109b+ci1
18:09:08.991  TlwCn : game activity started: com.google.firebase.MessagingUnityPlayerActivity
```

重启后缓存仍为 4789 个 `__data` / 4790 个 `__info`（1.49 GB），UI/角色名保持中文；
截图 `docs/screenshots/real-04-repair-button.png`、`real-05-after-repair.png`。
