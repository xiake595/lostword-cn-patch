# 构建准备

Windows + PowerShell，安装 JDK（含 javac/java/keytool）、Android SDK（platforms 与 build-tools，含 aapt2/zipalign/apksigner）、Python 3 和 R8/D8。设置 JAVA_HOME、ANDROID_SDK_ROOT，Python 加入 PATH 或使用 -PythonExe 指定。

R8 可以使用已有本地 r8.jar，通过 -R8Jar 指定；仓库不捆绑第三方工具。root 安装与 FPS 工具另外需要 Android platform-tools 的 adb，加入 PATH 即可。

## 本地签名

使用自己的密钥，默认别名 tlw；例如通过 JDK keytool 交互生成，密码按提示输入：

```powershell
keytool -genkeypair -keystore '本地签名.jks' -alias tlw -keyalg RSA -keysize 2048 -validity 10000
```

构建前在当前 PowerShell 设置 TLW_KEYSTORE_PASSWORD，构建后可用 `Remove-Item Env:TLW_KEYSTORE_PASSWORD` 清除。当前脚本使用相同的 keystore/key 密码，通过环境变量传给 apksigner。不要提交密钥或包含真实密码的配置。

新生成的签名与作者旧签名不同，不能覆盖旧签名包；后续自行升级需持续使用同一密钥。作者旧签名不在仓库中分发。

## 外部输入

仅使用同一游戏版本的 base 与 arm64 split，分别放在所构建模块的 apk/base.apk 与 apk/split_arm64.apk。汉化合并版还需要 assets/lwlocal.zip，下载与校验值见根 README。缺少这些输入时，源码仓库不能直接产出可安装的游戏 APK。

检查成品时应运行 apksigner verify、zipalign 检查、aapt2 dump badging，并核对包名、版本、启动 Activity、ABI 与保留的原资源。新游戏版本还需验证 Unity 偏移和中文缓存的实际行为。
