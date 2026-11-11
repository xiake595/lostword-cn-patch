# 东方归言录：简体汉化与帧率解锁

国际服简体中文汉化、独立帧率解锁，以及两者合并的 APK 构建项目。仓库按功能分为三个目录，保存源码、脚本、必要图标与技术文档。

当前国际服适配基线为 **1.58.0 / versionCode 7016 / arm64-v8a**，包名 `jp.goodsmile.touhoulostwordglobal_android`；**1.57.0 / 6728** 亦可构建（替换 `apk/` 下的 base 与 split，步骤见 [换数据包检查清单](integrated/docs/CHECKLIST-new-datapack.md)）。FPS 悬浮窗另保留日服 **1.71.1** 的构建入口；汉化与合并版仅针对国际服。合并版还支持**等长改名的共存版**（`-Pkg jp.goodsmile.touhoulostwordglobal_andr0id`，可与官方客户端并存），并带旧表清理、版本校验和「还原官方缓存」兜底，见 [共存版 ci3 记录](integrated/docs/BUILD-1.58.0-coexist-ci3.md)。

## 目录与选择

| 目录 | 内容 | 使用方式 |
|---|---|---|
| [cn-patch](cn-patch/README.md) | 汉化安装器源码、root 安装/还原脚本、数据规格与分析工具 | 只需要汉化；旧 LSPatch 模块由 Release 获取 |
| [unlock-FPS](unlock-FPS/README.md) | APK 内置悬浮窗源码、独立 root/ADB 工具 | 只需要帧率解锁 |
| [integrated](integrated/README.md) | 汉化首启安装器 + FPS 悬浮窗的合并构建 | 一个 APK，首启离线解包汉化数据，无需 root/LSPatch |

源码仓库不包含游戏原始安装包、汉化大数据包、生成的 APK/dex/class、反编译输出、设备缓存、第三方 SDK/ADB/R8，以及签名密钥。这些输入与工具需自行准备，见 [构建准备](docs/BUILDING.md)。原工作目录及安装包留在本地。

## 下载与安装

[Releases](https://github.com/xiake595/lostword-cn-patch/releases) 保留既有汉化发布；本次整理不发布新的二进制成品。**v1.3 / v1.4 是汉化数据版本**，并不代表 FPS 或合并版的版本。v1.3 对应游戏 1.57.0，v1.4 适配 1.58.0。

- 汉化数据：v1.4 的 `lwlocal.zip`（适配 1.58.0）、`version.txt`；v1.3 仍可用于 1.57.0。旧手机模块：`LwLocal-1.4.1.apk` / `LwLocal-1.3.apk`。
- 只用汉化：见 [cn-patch 使用说明](cn-patch/README.md)。
- FPS 与合并版：按各目录 README 自行构建；GitHub 的“Download ZIP”仅含源码。

`lwlocal.zip` SHA-256：

| 版本 | SHA-256 | 大小 | 解包后 | 内容 |
|---|---|---|---|---|
| v1.4 | `9b6f1c90269278b85d1bee80d7ff11aedd2e6b742673076d5fab5b92e9b2c7e2` | 378,134,402 B（360.6 MiB） | 438,036,025 B | **70 张表 + 345 个资源包（自带 345 个 `__info`）+ version.txt** |
| v1.3 | `a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792` | 445,336,186 B（424.7 MiB） | 445,234,868 B | 84 个 master 文件（83 张表 + manifest.json）+ 345 个资源包 + version.txt |

合并版会为资源包额外生成 345 个 `__info`；v1.4 自带的 `__info` 时间戳是打包时的固定值，安装器按 `__data` 的真实 mtime 重新生成。

## 当前行为与限制

- 合并版首启解包，后续按版本标记快速进入游戏；升级标记会触发重新安装汉化数据。修复了缺少 Unity `__info` 导致中文缓存被丢弃的问题，并提供悬浮窗“缓存修复”按钮。
- 安装器会记录本次写入的主表与资源包清单（`files/tlw_cn/installed.list`、`installed.bundles`），下次安装时清掉「上次写过、但新数据包已不含」的条目；只删自己写过的，游戏自行下载的表不受影响。对更早的 v1.3/ci1 装机（没有清单）用内置 `assets/tlw_cn_legacy.txt` 兜底清理；数据包还会写入适配的 `-GameVersion`，与客户端 `versionName` 不符时拒绝解包。这一组修复了 v1.3→v1.4 主表由 84 张减到 70 张时、残留旧表导致商店面板 `NullReferenceException` 黑屏的问题，详见 [故障排查](integrated/docs/TROUBLESHOOT-shop-black-screen.md)。
- 悬浮窗新增「还原官方缓存」兜底：黑屏/进不去主界面时删掉安装器写过的汉化数据并跳过解包重启，由游戏重下官方数据；想恢复汉化再点「缓存修复」。解包失败界面另提供「跳过汉化，直接启动游戏」。
- FPS 悬浮窗支持设置目标帧率、还原默认、隐藏与拖动；实际帧率受屏幕刷新率、vsync、温控和设备性能影响。
- 汉化覆盖剧情、部分 UI、字体及主数据表，仍有任务说明、派遣界面等未翻译内容。定位报告见 [派遣 UI 分析](cn-patch/docs/LOCALIZATION-errand-ui.md)，该报告不代表已完成翻译。
- v1.4 起**任务（课题）与交换所/商店的主表暂不汉化**，界面保持英文，以避开版本更新时的表结构变动；1.58 新增的 `another`、`event78` 两个剧情篇章尚未翻译。
- 重打包会改变签名。同包名无法直接覆盖官方客户端，卸载会删除本地数据；先确认引继方式。自行生成的签名也不能覆盖旧作者签名的补丁包。Google 登录可能受签名校验影响。
- 游戏更新后，需重新核对原始 APK、ABI、偏移与汉化数据兼容性。历史测试记录针对当时环境，未承诺其他版本。

整理记录与文件来源见 [仓库维护说明](docs/REPOSITORY.md)。
