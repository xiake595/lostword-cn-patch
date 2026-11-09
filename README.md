# 东方归言录（国际服）简体中文汉化补丁

> 包名 `jp.goodsmile.touhoulostwordglobal_android` · 对应游戏版本 **1.57.0 (6728)**

## 下载

**最新版：v1.3** → [Releases](https://github.com/xiake595/lostword-cn-patch/releases/latest)

| 文件 | 说明 |
|---|---|
| `LwLocal-1.3.apk` | 汉化模块（16 KB，只有代码） |
| `lwlocal.zip` | 汉化数据（424.7 MB / 429 个文件） |
| `version.txt` | 版本标记 |
`apply.sh` / `一键安装.bat` / `一键还原.bat` | 模拟器（root）一键安装 / 还原 |

> **详细操作指南**：[INSTALL.md](INSTALL.md) —— 模拟器与手机两种方式的分步教程、故障对照表

## 更新记录

### v1.3
- **剧情主角台词全部汉化**：9,851 条，覆盖 4,833 个对话对象 / 206 个资源包
- **技能名 / 符卡名 / 能力名汉化**：5,117 条（10 张主数据表）
- 保留富文本标记（`<color>`、`{0}` 占位符、`\x1b` 玩家名占位符）

### v1.2
- 补翻国际服专属技能/能力/符卡**说明句** 2,525 条
- 术语统一（迅速 / 结界异常 / HP / 全角括号）、角色名统一（姥芽 / 驯子 / 千亦）

### v1.1
- 字体按国服还原（英雄黑体 + 粗雅宋）、TMP `等级` 方块修复、排序筛选界面汉化、补 `enText` 字段

## 已知未完成

- 任务说明（如 `Log in on 5 days`）仍为英文
- 部分 UI 标签（`Switch Effect` 等）仍为英文
- 伙伴一览卡片角上的职业标记 `ATK/SUPP` 是图片，未替换

## 两种用法

### A. 非 root 手机（LSPatch 模块）
1. 装 [LSPatch](https://github.com/JingMatrix/LSPatch/releases)（Android 15/16 用 JingMatrix 版）
2. 用 LSPatch 给游戏打补丁，模块选 `LwLocal-1.3.apk`
3. 卸载原版 → 安装补丁版（签名不同必须卸载，账号在服务器不受影响）
4. 首次启动自动下载 `lwlocal.zip`

模块内置多源回退：GitHub → gh-proxy → ghproxy.net → 127.0.0.1:8899。

### B. 模拟器（已 root）
一键脚本见 v1.0，数据目录结构相同。

## 数据落在哪

| 内容 | 目标路径 |
|---|---|
| 84 张主数据表 | `files/cache/` |
| 345 个资源包 | `Android/data/<包名>/files/UnityCache/Shared/<包名>/<哈希>/__data` |

## 校验

v1.3 数据包 SHA-256：`a96657bfecd65a4eb1f84ea2055b927956c4ac8c29bcd66650217a1307030792`
