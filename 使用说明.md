# 东方归言录（国际服）简体中文汉化补丁

适用于 **已 root 的安卓模拟器**（雷电 / MuMu 等）。

- 游戏版本：**1.57.0**（versionCode 6728）
- 补丁版本：v1.0（2026-11-08）

## 下载

本仓库只放脚本和清单，**资源数据在 Releases**：

> https://github.com/xiake595/lostword-cn-patch/releases/latest

下载 `lostword-cn-patch-v1.0.zip`（约 367 MB），解压后得到：

    东方归言录汉化插件/
    ├─ 一键安装.bat
    ├─ 一键还原.bat
    ├─ 使用说明.md
    ├─ manifest.json
    ├─ 数据/
    └─ adb/

## 安装

1. 启动模拟器（游戏不用打开）
2. 双击 `一键安装.bat`
3. 等 1~2 分钟（会显示推送进度），脚本自动重启游戏

设备号不是 `emulator-5554` 时：

    一键安装.bat 你的设备号

## 还原

双击 `一键还原.bat`，会按安装时记录的清单删除文件，不影响游戏其他缓存。

## manifest.json

记录本补丁对应的游戏版本与 340 个资源包的哈希：

    {
      "game_version": "1.57.0",
      "version_code": 6728,
      "bundles": { "<包名>": "<哈希>", ... },
      "master_tables": [ ... ]
    }

安装脚本会读取设备上的 `versionName` 做比对，版本不符会警告。
将来做增量更新时，也靠它判断哪些包变了。

## 原理

通过 root 直接把文件写入游戏目录：

    数据/bundles/<包名>/<哈希>/__data  →  Android/data/<包名>/files/UnityCache/Shared/
    数据/master/<哈希>                →  /data/data/<包名>/files/cache/（并 chown 成游戏 uid）

不修改 APK，不动签名。

## 内容

| 模块 | 规模 |
|---|---|
| 剧情 | 271 包 / 152,032 行 |
| UI | 67 包 |
| 字体 | 2 包（正文宋体 / 界面黑体） |
| 主数据表 | 84 张 |

约 16.5 万条复用国服官方中文，其余为翻译。

## 已知问题

- Exchange / Errand 按钮图仍为英文（国服同名 sprite 缺失）
- 活动横幅由服务器下发，无法替换
- 「已完成！」标签比「新开启！」偏大，未定位

## 免责

本项目仅供学习交流，请于下载后 24 小时内删除。
游戏资源版权归 Good Smile Company / Team Shanghai Alice 所有。
使用本补丁产生的任何后果由使用者自行承担。