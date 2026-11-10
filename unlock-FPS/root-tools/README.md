# root / ADB 帧率工具

Windows 菜单与 shell 脚本，适用于已 root 的设备或模拟器。游戏安装包保持原样，通过内存写入设置 Unity 的目标帧率。

## 使用

安装 Android platform-tools，将 adb 加入 PATH，运行 `归言录工具.bat` 并选择帧率操作。批处理也会检测本地 adb 目录及部分模拟器的 adb；仓库不再捆绑工具二进制。

多开管理可使用：

```powershell
.\tlw_multi.ps1 -Adb '本地adb.exe路径' -Fps 165
.\tlw_multi.ps1 -Adb '本地adb.exe路径' -Status
.\tlw_multi.ps1 -Adb '本地adb.exe路径' -Stop
```

目标帧率需结合屏幕刷新率选择。165 是历史测试设备的示例值，不是所有设备都能达到；重启进程后内存设置会失效，可使用菜单中的守护功能持续应用。

## 文件

| 文件 | 作用 |
|---|---|
| `归言录工具.bat` | Windows 菜单与设备检测 |
| `tlw_common.sh` | 包名、版本、内存与偏移公共函数 |
| `tlw_fps.sh` | 帧率定位与内存写入 |
| `tlw_elf_scan.ps1` | 在电脑上扫描 libunity.so 的目标帧率偏移 |
| `tlw_multi.ps1` | 多设备帧率管理 |
| `tlw_guard.sh` / `tlw_guard_loop.sh` | 守护入口与循环 |
| `tlw_reroll.sh` | 原有刷号/缓存备份回填功能 |
| `tlw_info.sh` | 设备与游戏信息 |

偏移扫描示例：`powershell -File tlw_elf_scan.ps1 本地libunity.so路径`。国际服 1.57.0 的历史偏移为 `0x199cc54`，游戏更新后需重新验证。

菜单还保留刷号、账号文件清理和资源缓存回填选项，这些操作会更改设备数据；只需帧率解锁时使用 FPS 相关选项。历史实测与原始操作记录在 `docs/history/README.md` 和 `使用说明.txt`，其中旧 Python 扫描器描述已由实际存在的 PowerShell 扫描器取代。
