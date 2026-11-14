# cn-patch：简体中文汉化

当前发布：**v1.5**（适配国际服 1.58.0，资源包 431 + 主表 79 + 剧情 271）→ [v1.5 说明](v1.5/README.md)

历史版本：v1.4（适配 1.58.0，LSPatch 模块 + 数据包）、v1.3（适配 1.57.0 / 6728）。

## 文件

| 路径 | 作用 |
|---|---|
| `src/tlw/cn/` | 合并版使用的首启解包安装器 `CnSetupActivity` 与缓存修复 `CacheRepair` 源码 |
| `一键安装.bat` / `一键还原.bat` / `apply.sh` | 既有 root/模拟器安装与还原脚本 |
| `manifest.json` | 既有汉化资源与主数据清单 |
| `docs/` | 数据布局、资源统计、尚未翻译 UI 的定位报告 |
| `tools/unityfs/` | UnityFS 解包与文本报告工具 |
| `tools/research/` | 分析脚本存档，依赖原工作区的缓存/反编译输入，使用前需调整路径 |

`src/tlw/cn` 是合并版安装器源码，需和 FPS 的宿主实现一起编译，入口在 [integrated](../integrated/README.md)。当前本地没有旧 `LwLocal-1.3.apk` 的 Java 源码，因此不把解包得到的 dex 当作源码提交；旧模块仍从 Release 获取。

## 使用既有汉化发布

从 [v1.3 Release](https://github.com/xiake595/lostword-cn-patch/releases/tag/v1.3) 获取 `lwlocal.zip`，校验 SHA-256：
`a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792`。

**root 设备/模拟器**：自行安装 Android platform-tools 并将 adb 加入 PATH，把 `lwlocal.zip` 放在本目录，连接设备后运行 `一键安装.bat 设备序列号`；省略参数时默认 `emulator-5554`。还原用 `一键还原.bat 设备序列号`。脚本需要 root，会覆盖游戏缓存；先关闭游戏并备份必要数据。

这些脚本保持原 v1.3 行为，`apply.sh` 只复制 `__data`，没有合并版新增的 `__info` 修复；若游戏下载后中文消失，推荐使用合并版。它们不等同于新版安装器。

**非 root 手机的旧 LSPatch 方式**：另下载 `LwLocal-1.3.apk`，使用适合设备系统版本的 LSPatch 给游戏嵌入模块，按模块流程下载汉化数据。签名变化前先确认引继方式；旧操作记录见 [v1.3 历史教程](docs/history/INSTALL.md)，工具兼容性请自行核对。

## 数据与开发

84 个 master 文件写入私有 `files/cache/`；345 个资源包写入外部 `UnityCache/Shared/<A>/<B>/__data`。当前合并版同时生成 `__info`，版本标记优先使用构建时注入的 `assets/tlw_cn.version`，避免数据包内旧 `version.txt` 造成误判。

这里只保存数据规格与分析工具，未收录完整汉化数据、翻译生成流水线或官方缓存，不能仅凭仓库重新生成 v1.3 汉化数据包。源码副本与 `integrated/src/tlw/cn` 保持一致，修改时同步两处。
