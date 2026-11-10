# 东方归言录：简体汉化与帧率解锁

国际服简体中文汉化、独立帧率解锁，以及两者合并的 APK 构建项目。仓库按功能分为三个目录，保存源码、脚本、必要图标与技术文档。

当前国际服适配基线为 **1.57.0 / versionCode 6728 / arm64-v8a**，包名 `jp.goodsmile.touhoulostwordglobal_android`。FPS 悬浮窗另保留日服 **1.71.1** 的构建入口；汉化与合并版仅针对国际服。

## 目录与选择

| 目录 | 内容 | 使用方式 |
|---|---|---|
| [cn-patch](cn-patch/README.md) | 汉化安装器源码、root 安装/还原脚本、数据规格与分析工具 | 只需要汉化；旧 LSPatch 模块由 Release 获取 |
| [unlock-FPS](unlock-FPS/README.md) | APK 内置悬浮窗源码、独立 root/ADB 工具 | 只需要帧率解锁 |
| [integrated](integrated/README.md) | 汉化首启安装器 + FPS 悬浮窗的合并构建 | 一个 APK，首启离线解包汉化数据，无需 root/LSPatch |

源码仓库不包含游戏原始安装包、汉化大数据包、生成的 APK/dex/class、反编译输出、设备缓存、第三方 SDK/ADB/R8，以及签名密钥。这些输入与工具需自行准备，见 [构建准备](docs/BUILDING.md)。原工作目录及安装包留在本地。

## 下载与安装

[Releases](https://github.com/xiake595/lostword-cn-patch/releases) 保留既有汉化发布；本次整理不发布新的二进制成品。既有 **v1.3 是汉化数据版本**，并不代表 FPS 或合并版的版本。

- 汉化数据：v1.3 的 `lwlocal.zip`、`version.txt`；旧手机模块：`LwLocal-1.3.apk`。
- 只用汉化：见 [cn-patch 使用说明](cn-patch/README.md)。
- FPS 与合并版：按各目录 README 自行构建；GitHub 的“Download ZIP”仅含源码。

v1.3 `lwlocal.zip` SHA-256：
`a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792`

数据包为 445,336,186 字节（约 424.7 MiB），解包数据 445,234,854 字节；包含 **84 个 master 文件（83 张表 + manifest.json）、345 个资源包和 1 个版本文件**。合并版会为资源包额外生成 345 个 `__info`。

## 当前行为与限制

- 合并版首启解包，后续按版本标记快速进入游戏；升级标记会触发重新安装汉化数据。修复了缺少 Unity `__info` 导致中文缓存被丢弃的问题，并提供悬浮窗“缓存修复”按钮。
- FPS 悬浮窗支持设置目标帧率、还原默认、隐藏与拖动；实际帧率受屏幕刷新率、vsync、温控和设备性能影响。
- 汉化覆盖剧情、部分 UI、字体及主数据表，仍有任务说明、派遣界面等未翻译内容。定位报告见 [派遣 UI 分析](cn-patch/docs/LOCALIZATION-errand-ui.md)，该报告不代表已完成翻译。
- 重打包会改变签名。同包名无法直接覆盖官方客户端，卸载会删除本地数据；先确认引继方式。自行生成的签名也不能覆盖旧作者签名的补丁包。Google 登录可能受签名校验影响。
- 游戏更新后，需重新核对原始 APK、ABI、偏移与汉化数据兼容性。历史测试记录针对当时环境，未承诺其他版本。

整理记录与文件来源见 [仓库维护说明](docs/REPOSITORY.md)。
