# 东方归言录（国际服）简体中文汉化补丁

> 包名 `jp.goodsmile.touhoulostwordglobal_android` · 对应游戏版本 **1.57.0 (6728)**

## 下载

**最新版：v1.1** → [Releases](https://github.com/xiake595/lostword-cn-patch/releases/latest)

| 文件 | 说明 |
|---|---|
| `LwLocal-1.1.apk` | 汉化模块（12 KB，只有代码） |
| `lwlocal.zip` | 汉化数据（424 MB / 429 个文件） |
| `version.txt` | 版本标记，模块用它判断要不要更新数据 |
| `INSTALL.md` | 安装说明 |

## v1.1 更新内容

- **字体按国服还原**：UI 用 `字魂3号英雄黑体`，正文用 `方正粗雅宋`（之前错用了宋体/黑体）
- 修复 TMP 界面 `等级` 显示成方块 → 改为 `Lv.`
- 排序 / 筛选界面整页汉化（等级、稀有度、界限突破、防御式 / 攻击式 …）
- 补上 `enText` 字段：此前汉化只写 `m_Text`，而英文模式下游戏读的是 `enText`，导致部分翻译未生效
- 新增 **LSPatch 模块**方案，非 root 手机可用

## 两种用法

### A. 非 root 手机（LSPatch 模块）

1. 装 [LSPatch](https://github.com/JingMatrix/LSPatch/releases)（Android 15/16 必须用 JingMatrix 版）
2. 用 LSPatch 给游戏打补丁，模块选 `LwLocal-1.1.apk`
3. 卸载原版 → 安装补丁版（签名不同，必须卸载；账号在服务器，不受影响）
4. 首次启动自动从本仓库 Releases 下载 `lwlocal.zip` 并解压

模块跑在游戏进程里、用游戏自己的 uid 写私有目录，所以 **不需要 root，也不需要 chown**。

### B. 模拟器（已 root）

见 [v1.0](https://github.com/xiake595/lostword-cn-patch/releases/tag/v1.0) 里的 `一键安装.bat`，数据目录结构相同。

## 数据落在哪

| 内容 | 目标路径 |
|---|---|
| 84 张主数据表 | `files/cache/` |
| 345 个资源包 | `Android/data/<包名>/files/UnityCache/Shared/<包名>/<哈希>/__data` |

## 汉化范围

| 模块 | 规模 |
|---|---|
| 剧情文本 | 271 个资源包 / 152,032 行 |
| UI 文字 | 67 个资源包 |
| 字体 | 2 个字体包 + 4 处 TMP/SDF 相关包 |
| 主数据表 | 84 张表 / 约 51 万条字符串 |

约 16.5 万条直接复用国服官方中文，其余为翻译（英文源 + 日语源校对）。

## 已知问题

- 伙伴一览卡片左上角的职业标记是**图片**（`ATK`/`SUPP`/`SPD` 竖排美术字），暂未替换
- `Exchange` / `Errand` 两个按钮图仍是英文（国服同名 sprite 缺失）
- 活动横幅是服务器下发的图，无法替换
- TextMeshPro 界面若出现中文方块，是因为 SDF 图集只烘焙了 80 个 ASCII 字符

## 校验

v1.1 数据包 SHA-256：`956309b2ebe9031a62aa84e2e424671f1a242d2dc5c3df34596678bed9ab8c48`
---

## ⚠️ 风险提示

1. **注入风险**：v1.1 用 LSPatch 注入游戏进程，部分游戏会检测注入框架，处罚可能是封号。**建议使用副号测试。**
2. **账号风险**：卸载原版会清空本地数据。**安装前请确认已绑定引继码**，否则可能找不回账号。
3. **版权**：游戏资源版权归 Good Smile Company / Team Shanghai Alice 所有，本项目仅供学习交流，请于下载后 24 小时内删除。

## 国内下载

GitHub Release 在国内直连较慢，可先把 `lwlocal.zip` 通过网盘/加速站下载下来，放到：

    Android/data/jp.goodsmile.touhoulostwordglobal_android/files/lwlocal.zip

模块启动时检测到本地包会跳过下载，直接解压。
