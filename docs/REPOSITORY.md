# 仓库维护与整理记录

2026-11-10，以远端 main 的 95343d1 为基础整理，保留既有 Git 历史与 Release。

| 原工作目录 | 仓库位置 |
|---|---|
| work/cn-patch（远端最新脚本） | cn-patch/ |
| integrated/src/tlw/cn 与数据规格 | cn-patch/src/、cn-patch/docs/ |
| work/cn-analysis、work/cn-triage 的自写 Python | cn-patch/tools/research/ |
| tlw/归言录内置悬浮窗 | unlock-FPS/overlay/ |
| tlw/归言录帧率解锁 | unlock-FPS/root-tools/ |
| integrated | integrated/ |
| transfer/TLW-cn-fps-project/docs/device-testing | integrated/docs/device-testing/ |

transfer 是交接副本，不重复收录整套项目。旧 README/安装教程保存在各模块 docs/history，保留历史数据与验证背景；当前入口以根 README、模块 README 和 BUILDING.md 为准。

排除原始游戏包、汉化 ZIP/解包目录、生成 APK/dex/class、反编译输出、设备资源缓存、临时分析结果、下载的第三方工具和签名材料。截图与技术调查属于不可由源码重新生成的验证记录，因此保留；日志中的设备标识以占位符替换。以上排除针对当前提交树，不重写旧提交历史，也不删除本地原工作资料。

构建入口补充了可配置工具链/签名参数，移除了固定签名密码，避免整理后依赖作者机器目录或私有签名。没有改动汉化/FPS 的运行时实现。旧 LSPatch 模块源代码与完整汉化数据生成流程在本地缺失，README 已明确记录。

维护 cn-patch/src/tlw/cn 与 integrated/src/tlw/cn 时同步修改；FPS 独立版与合并版的 UI 入口有差异，不可直接覆盖。研究脚本保留原始路径假设，需准备对应输入并按目录迁移后再运行。

## 本次验证

独立 FPS 与合并版均通过完整构建（javac、D8、AXML 编辑、repack、zipalign、apksigner），输入来自本机仓库外的官方 APK、v1.3 汉化数据、R8 与既有本地签名；构建产物留在忽略目录，不随本次提交上传。合并版核对包名、1.57.0/6728、启动 Activity 与 arm64 ABI；两版的原始 resources.arsc 与游戏 dex 均作保留检查。另检查 Python/PowerShell 语法、当前文档本地链接及提交文件类型。本次未重新进行设备安装或游戏内验证。

2026-11-11 补充：合并版升级到 1.58.0 / 7016 + v1.4 数据，并新增共存版构建（`-Pkg …_andr0id`、等长改应用名、独立 authority）、安装器 legacy 旧表清理与游戏版本校验、悬浮窗「还原官方缓存」和解包失败「跳过汉化」兜底。共存版已在 HyperOS 真机完成安装与首启解包验证（`entries=416 seen=761 master=70 bundles=345`，24 秒；二次启动快路径；FPS `via 内置 1.58.0`；无 FATAL），登录与资源下载留给使用者手动完成，详见 [共存版 ci3 记录](../integrated/docs/BUILD-1.58.0-coexist-ci3.md)。

## GitHub About 描述

建议描述：`东方归言录：简体中文汉化（cn-patch）、帧率解锁（unlock-FPS）与合并版构建源码、脚本及文档`。

本次使用的合作者账号可推送 main，但 API 返回 admin=false、maintain=false。更新仓库描述的 PATCH 请求返回 404，About 需由有仓库管理权限的维护者设置；代码和 README 不受影响。

2026-11-14 补充：合并汉化 v1.5（1.58.0，79 张主表 + 431 个资源包，647 MiB）到 integrated，重建共存版 APK（814,145,118 B，sha256 29637B2F…1733）；安装器清理逻辑改为「主表按大小校验才删」，legacy 清单缩到 5 条且不含 UnitMaster，以规避主数据整包重下覆盖汉化；同时清理了本机过时的工作目录与旧产物。出包记录见 [v1.5 记录](../integrated/docs/BUILD-1.58.0-v15.md)。
