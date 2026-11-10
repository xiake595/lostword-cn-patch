# unlock-FPS：帧率解锁

| 目录 | 方式 | 条件 |
|---|---|---|
| [overlay](overlay/README.md) | 向游戏 APK 注入 Java/dex 悬浮窗，在游戏进程内设置目标帧率 | 使用重打包客户端，无需 root |
| [root-tools](root-tools/README.md) | Windows 菜单 + ADB/shell，在运行中的游戏内存设置帧率 | 设备/模拟器有 root |

国际服基线 1.57.0；悬浮窗另保留日服 1.71.1 与共存版参数。两种实现均保留源码，第三方 adb、SDK、游戏原始安装包和生成 APK 需另行准备。

`root-tools` 的原菜单还包含刷号与缓存回填功能，执行相关选项会清理账号文件；仅需要 FPS 时选择帧率相关操作。原说明中列出的设备实测值属于历史记录，实际帧率取决于当前设备。

需要汉化与 FPS 同时使用，见 [合并版](../integrated/README.md)。
