# 东方归言录（国际服）简体中文汉化补丁

> 包名 `jp.goodsmile.touhoulostwordglobal_android` · 对应游戏版本 **1.57.0 (6728)**

## 下载

**最新版：v1.2** → [Releases](https://github.com/xiake595/lostword-cn-patch/releases/latest)

| 文件 | 说明 |
|---|---|
| `LwLocal-1.2.apk` | 汉化模块（12 KB，只有代码） |
| `lwlocal.zip` | 汉化数据（424.8 MB / 429 个文件） |
| `version.txt` | 版本标记 |
| `INSTALL.md` | 安装说明 |

## v1.2 更新内容

- 补翻**国际服专属**技能/能力/符卡说明 **2,525 条**（国服没有对应文本的部分）
- 术语按国服统一：迅速 / 结界异常 / 金属 / HP / 全角括号
- 修正国际服原创角色译名：姥芽 / 驯子 / 千亦
- 修复技能效果仍显示英文的问题（例：芙兰朵露「Black Bonnet」描述已中文化）

## 已知未完成

- 约 5,100 条**技能名/符卡名**（短名）仍为英文，待下一版补
- 约 450 条长句说明仍为英文

## 两种用法

### A. 非 root 手机（LSPatch 模块）

1. 装 [LSPatch](https://github.com/JingMatrix/LSPatch/releases)（Android 15/16 必须用 JingMatrix 版）
2. 用 LSPatch 给游戏打补丁，模块选 `LwLocal-1.2.apk`
3. 卸载原版 → 安装补丁版（签名不同，必须卸载；账号在服务器，不受影响）
4. 首次启动自动从 Releases 下载 `lwlocal.zip`

### B. 模拟器（已 root）

见 v1.0 里的一键安装脚本，数据目录结构相同。

## 数据落在哪

| 内容 | 目标路径 |
|---|---|
| 84 张主数据表 | `files/cache/` |
| 345 个资源包 | `Android/data/<包名>/files/UnityCache/Shared/<包名>/<哈希>/__data` |

## 校验

v1.2 数据包 SHA-256：`039da1b6853c5aaf95ccbe31431bd37d4e6536eb95ceed995590280ad5d3fc03`
