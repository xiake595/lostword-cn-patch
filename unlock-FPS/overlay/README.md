# APK 内置帧率悬浮窗

源码在 `src/tlw/fps/`，`TlwBoot` 启动内核，`UnityFps` 定位 Unity 目标帧率，`FpsOverlay` 提供浮球与设置面板。授予“显示在其他应用上层”后使用系统悬浮窗，未授权时保留游戏内视图兜底。

支持拖动、设置 10～480 的目标帧率、还原默认 `-1`、隐藏与恢复。目标值不是实测 FPS；应结合屏幕刷新率与性能选择。

## 构建

先按 [构建准备](../../docs/BUILDING.md) 安装工具并准备自己的签名，原始国际服文件放 `apk/base.apk` 与 `apk/split_arm64.apk`。在本目录执行：

```powershell
$env:TLW_KEYSTORE_PASSWORD = Read-Host '本地签名密码'
.\build.ps1 -JdkHome $env:JAVA_HOME -SdkRoot $env:ANDROID_SDK_ROOT -PythonExe python -R8Jar '本地的r8.jar路径' -KeyStore '本地的签名.jks路径'
```

输出 `out/TLW-global-1.57.0-fps.apk`。默认密钥别名为 `tlw`，可用 `-KeyAlias` 修改。脚本不生成或分发作者签名；安装到已有补丁客户端时须使用相同签名。

国际服共存版需指定等长 `-Pkg`、可选等长 `-Label`，以及独立 `-Authority`。日服共存参数在 `build-jp-coexist.ps1`；运行前设置 JAVA_HOME、ANDROID_SDK_ROOT，并在本目录准备已忽略的 r8.jar 与 tlw-release.jks、`apk/jp/` 原始 APK。日服覆盖版也可使用 `build.ps1` 的 `-BaseApk`、`-SplitApk`、`-OldPkg`、`-OldLabel`、`-Authority`、`-Out` 参数。

`install.ps1` 是 root 设备的备份/卸载/安装辅助脚本，会更改设备上的游戏安装与数据，请先阅读脚本再使用。源码整理过程没有执行它。

旧版实现细节与实测记录保存在 `docs/history/`；其中本机工具路径和签名说明已被当前构建参数取代。合并版的 FPS 源码另有汉化安装器调用，修改两套代码时需要检查差异。
