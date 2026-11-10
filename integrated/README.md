# 合并版：简体汉化 + 帧率悬浮窗

一个重打包 APK 内含 FPS 悬浮窗与汉化数据。首启由 `tlw.cn.CnSetupActivity` 在游戏进程内解包汉化数据，然后进入游戏；以后按版本标记走快速启动。不需要 root、ADB 或 LSPatch 来运行成品。

适配国际服 **1.57.0 / 6728 / arm64-v8a / Android 7.0+**，保留官方包名、应用名及 resources.arsc。签名改变，同包名无法覆盖官方客户端。

## 构建

按 [构建准备](../docs/BUILDING.md) 配置 JDK、Android SDK、Python、R8 与本地签名。另行准备：

| 本地路径 | 输入 |
|---|---|
| `apk/base.apk` | 官方国际服 1.57.0 base |
| `apk/split_arm64.apk` | 同一版本 arm64 ABI split |
| `assets/lwlocal.zip` | [v1.3 Release](https://github.com/xiake595/lostword-cn-patch/releases/tag/v1.3) 汉化数据 |
| `assets/tlw_icon.png` | 仓库内必要悬浮球图标 |

在本目录运行：

```powershell
$env:TLW_KEYSTORE_PASSWORD = Read-Host '本地签名密码'
.\build-cn.ps1 -JdkHome $env:JAVA_HOME -SdkRoot $env:ANDROID_SDK_ROOT -PythonExe python -R8Jar '本地的r8.jar路径' -KeyStore '本地的签名.jks路径'
```

默认输出 `out/TLW-global-1.57.0-cn-fps.apk`。可指定 `-KeyAlias`、`-Out`、`-BaseApk`、`-SplitApk`、`-CnZip`、`-Icon`、`-Authority`、`-CnVersion`。默认数据标记 `v1.3-20261109b+ci1`；更换数据后应同时修改标记。

流水线：javac → D8 → 二进制 AXML 修改 → 合并 base/split、dex、图标与数据 → zipalign → apksigner。数据包以 STORED 方式内置。原始安装包、大数据包、密钥、工具二进制及所有生成输出均不进入 Git。

## 使用与修复

安装前确认账号引继方式并备份必要数据。卸载官方客户端会删除本地数据；不同签名无法覆盖升级。使用同一份本地签名的旧补丁可尝试覆盖安装，但需确保游戏版本兼容。

首次启动等待汉化解包完成，后续直接进入游戏。Unity 缓存会同时写 `__data` 和 `__info`；中文回退英文时可点击面板中的“缓存修复”，它会清除安装标记并重启重装汉化缓存。

详见 [使用说明](docs/使用说明.md)、[缓存问题调查](docs/INVESTIGATION-cn-cache-info.md)。历史设备验证、日志与截图保存在 `docs/`；本次整理仅重新编译和静态检查，不代表对新系统或新游戏版本进行了真机验证。

`src/tlw/cn` 与 `cn-patch/src/tlw/cn` 为相同安装器的源码副本；`src/tlw/fps` 包含合并版特有的缓存修复入口。旧完整构建记录见 [历史 README](docs/history/README.md)。
