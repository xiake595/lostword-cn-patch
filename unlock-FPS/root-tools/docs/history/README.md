# 东方归言录 刷初始号（免下载）+ 帧率解锁

## 一分钟上手

```
1. 解压，双击 归言录工具.bat
2. 选 1（环境自检），确认 root / 包名 / 版本都打勾
3. 选 2（做备份），等几分钟 —— 只需做一次
4. 以后每次刷号选 3，过教程时点 Cancel 不点 Confirm
```

## 环境要求

| 项目 | 要求 |
|---|---|
| 模拟器 | MuMu 12 / MuMu 15 / 雷电 14（其他未测试） |
| 系统 | Android 8.0+ |
| root | **必须**。模拟器设置里开启 |
| 游戏 | 国际服 `jp.goodsmile.touhoulostwordglobal_android`<br>日服 `jp.goodsmile.touhoulostword_android`<br>国服 `com.gg.touhoulw` |
| adb | 放在 bat 同级 `adb\adb.exe`，或已在 PATH |
| Python 3 | **不需要**（偏移探测用 PowerShell + 内联 C#） |

bat 会自动扫描常见端口，并从 MuMu 的 `vm_config.json` 读取真实 adb 端口，
不限实例数量。同时开着多台模拟器时会列出设备让你选。

---

# 一、刷初始号：免下 646MB

## 原理

游戏有两层资源，行为完全不同：

| 层 | 位置 | 格式 | 清号后 |
|---|---|---|---|
| 原始 bundle | 内部 `files/cache` | `EAST` 头 + JSON 清单 | **从不被删** |
| Unity 缓存 | 外部 `UnityCache/Shared` | `UnityFS` (AssetBundle) | **教程结束时清空**，要求重下 646MB |

关键发现：游戏清空 `UnityCache` 后，会**停下来弹框等你确认**。这段窗口期不会下载。
趁这个空档把备份塞回去，然后点 Cancel，游戏就直接读缓存了。

守护进程每 2 秒检查一次，发现被清空就立刻回填。

## 实测时间线

```
04:41:39  UnityCache 被清空 (868008KB → 24KB)
          ↓  ← 空窗期，游戏在等你点 Confirm
04:42:55  回填完成 (24KB → 868076KB)
          ↓
          Cancel → Game Start
          ↓
          ✅ 直接进剧情，立绘背景全部正常
```

进游戏后 UnityCache 只涨了 3MB，不是重下 646MB。

## 之前失败的三种方案

| 方案 | 做法 | 结果 |
|---|---|---|
| A | 只删账号 6 个文件 | ❌ 教程结束清空 UnityCache |
| B | 删账号但保留 `eastreg.ini` | ❌ 账号登录回去了，没变新号 |
| C | 藏起 UnityCache → 删号 → 改回 | ❌ 教程结束照样清空 |

**方案 B 的教训**：`eastreg.ini` 就是账号凭据本身。保住它，账号就回来了，所以必须删。

**方案 C 的教训**：清空时机是**教程结束时**，不是启动时。启动前藏起来没用。

## 注意事项

1. **备份只有一份，别删** `UnityCache.bak`（约 870MB）
2. **备份可无限次使用**（回填用 `cp -a`，不消耗）
3. **游戏大版本更新后要重做备份**（旧备份和新版本不匹配）
4. **如果游戏没弹框就开始下载**：用菜单 5 手动回填，然后 Cancel
5. **改的是内存和缓存，不动 APK**，存档和账号安全

---

# 二、帧率解锁

## 为什么国际服只有 27.5fps

游戏没调 `set_targetFrameRate`，Unity 默认 `-1` 触发回落逻辑，用硬编码 30fps，
再被 vsync 量化：

```
165Hz / 6 = 27.5fps   ← 你看到的
```

写 144 没用（不是 165 的整数分之一）。**要满帧就写 165。**

## 实测数据

| targetFrameRate | 实测 fps | 帧间隔 |
|---|---|---|
| -1（默认） | 27.5 | 36.36 ms |
| 55 | 55.0 | 18.18 ms |
| 82 | 82.5 | 12.12 ms |
| 165 | 165.0 | 6.07 ms |

## 自动探测偏移

游戏更新后偏移会变。工具会自动探测：

```powershell
# 从 APK 提取 libunity.so，扫指令特征定位
powershell -File tlw_elf_scan.ps1 libunity.so
# 输出: 0x199cc54
```

**探测原理**：Unity 的访问函数签名极其规整：

```asm
get_targetFrameRate:          set_targetFrameRate:
    adrp  x8, <page>              adrp  x8, <page>
    ldr   w0, [x8, #imm]          str   w0, [x8, #imm]
    ret                           b     <...>
```

两者指向同一地址。用 **getter ∩ setter 取交集**，从 131 个 getter 候选收敛到唯一结果。

实测：libunity.so 里 13 个 getter + 2 个 setter，交集只有 `0x199cc54`，与手动逆向结果完全一致。

## 已知偏移表

| 游戏版本 | 偏移 |
|---|---|
| 1.57.0 | `0x199cc54` |

版本变了工具会自动探测，不用手动改。

## 帧率注意事项

1. 需要 root
2. 改内存不动 APK
3. 切场景不会回锁（实测 7 次界面切换稳定 165）
4. 别写 144 或 120，会被量化
5. 游戏重启后值会丢，需要重新设置（或开守护）

---

# 三、文件说明

| 文件 | 作用 |
|---|---|
| `归言录工具.bat` | 主菜单，自动探测 adb / 端口 / 包名 |
| `tlw_common.sh` | 公共函数：包名、版本、基址、偏移表 |
| `tlw_reroll.sh` | 刷号：check / prep / start / restore / status / stop |
| `tlw_guard_loop.sh` | 后台守护，2 秒检测，自动回填 |
| `tlw_fps.sh` | 帧率：自动探测偏移 + 写入 |
| `tlw_elf_scan.py` | ELF 解析器，从 libunity.so 定位偏移 |

## 命令行用法（不用 bat）

```bash
adb push tlw_*.sh tlw_elf_scan.py /data/local/tmp/
adb shell chmod 755 /data/local/tmp/tlw_*.sh

adb shell su -c "sh /data/local/tmp/tlw_reroll.sh check"    # 自检
adb shell su -c "sh /data/local/tmp/tlw_reroll.sh prep"     # 备份
adb shell su -c "sh /data/local/tmp/tlw_reroll.sh start"    # 刷号
adb shell su -c "sh /data/local/tmp/tlw_fps.sh"             # 解锁帧率
adb shell su -c "sh /data/local/tmp/tlw_fps.sh 0"           # 还原帧率
```

---

# 四、踩坑记录（给遇到问题的人）

## bat 报错一闪而过

**原因**：bat 存成 UTF-8 带中文，cmd.exe 按 GBK 解析时字节错位，整行被截断。

**解决**：纯 ASCII + CRLF。本工具已处理。

## 菜单选项读不到

**原因**：`adb push` 会吃掉 stdin，导致 `set /p` 读不到输入。

**解决**：所有 adb 调用加 `<nul`。本工具已处理。

## 偏移写错导致崩溃

**原因**：`$((0x$BASE + $OFF))` 里 `$OFF` 已带 `0x` 前缀，拼成 `0x0x199cc54`。

**解决**：先 `sed 's/^0x//'` 去前缀。本工具已处理。

## 刷号后账号没变

**原因**：`eastreg.ini` 没删干净。它存的是账号凭据。

**解决**：`tlw_reroll.sh start` 会自动删它。

## 刷号后仍要下载

**原因**：UnityCache 被清空后没及时回填，游戏开始下载了。

**解决**：用菜单 5 手动回填，然后点 Cancel。

---

# 五、免责

- 工具只读写本机内存和缓存文件，不修改 APK，不联网
- 刷初始号属于利用游戏机制，是否影响账号由游戏厂商判定
- 帧率解锁修改的是运行时内存，游戏更新后需重新适配
- 请自行评估使用风险
