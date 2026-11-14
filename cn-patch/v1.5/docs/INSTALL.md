# v1.5 安装说明

适配国际服 **1.58.0**，包名 `jp.goodsmile.touhoulostwordglobal_android`。

不修改 APK、不改变签名，随时可还原。

## 需要什么

1. **游戏已安装并至少启动过一次** —— 要它先把自己的资源缓存目录建出来
2. **设备已 root** —— 写游戏私有目录需要。模拟器一般自带，真机需自行解决
3. **adb 可用** —— 脚本按顺序找：环境变量 `ADB` → `C:\leidian\LDPlayer14\adb.exe` → PATH 里的 `adb`
4. **Python 3.9+**

## 三步装好

先把 Release 里的 `tlw-payload-v1.5.zip` 解压到本目录，让 `payload/` 和 `tlw_install.py` 同级：

```
tlw_install.py
一键安装.bat
SHA256SUMS.txt
payload/
  meta.json
  bundles.json     431 个资源包
  masters.json      79 张主表
  story.json       271 个剧情包
  uc/              资源包文件
  master/          主表文件
  story/           剧情包文件
```

然后：

```bash
python tlw_install.py install     # 装
python tlw_install.py verify      # 查
python tlw_install.py restore     # 还原成英文
```

或者双击 `一键安装.bat`，菜单式选择。

**换设备**加 `--serial`：

```bash
python tlw_install.py install --serial 127.0.0.1:5555
```

**只看会做什么、不写入**：

```bash
python tlw_install.py install --dry-run
```

## 安装时脚本做了什么

| 步骤 | 写入位置 | 数量 |
|---|---|---|
| 1/3 资源包 | `Android/data/<pkg>/files/UnityCache/Shared/<A>/<B>/__data` | 431 |
| 2/3 主表 | `/data/user/0/<pkg>/files/cache/<hash>` | 79 |
| 3/3 剧情 | 同资源包路径，但**会主动创建**设备上不存在的条目 | 271 |

**资源包和剧情的 `__info` 契约**：写完必须同时写 `-1\n<epoch>\n1\n__data`，`epoch` 等于新 `__data` 的 mtime。否则 Unity 判定缓存失效会重新下载，补丁被覆盖。

**主表**：AES-128-CBC 加密，写完 `chown <游戏UID>` + `chmod 600`。脚本从设备实时读 UID，不写死。

**备份**：改动前把原文件存到设备 `/data/local/tmp/tlw-v15-backup/`，`restore` 从这里恢复。

## 装完怎么确认

1. 重启游戏
2. 进**伙伴**界面 → 角色列表正常显示（不黑屏）
3. 进**绘卷**界面 → 绘卷名和说明是中文
4. 进**主线/活动剧情** → 对话是中文，不黑屏

再跑一遍 `verify`，三类都显示「一致 全部 / 不一致 0」就算装好了。

## 常见问题

**某处还是英文？**
那个界面还没被游戏加载过，对应缓存条目不存在。进该界面一次，再重跑 `install` 补上（脚本会自动跳过设备上没有的条目）。

**装完闪退 / 界面黑屏？**
先 `restore` 还原，确认游戏正常，再把错误信息发出来。剧情黑屏通常意味着该篇章的资源包与游戏版本不匹配。

**游戏更新后补丁失效？**
补丁绑版本号。更新后需要重新制作对应版本的补丁，不要强行套用。

**还原后还是中文？**
重启游戏。如果仍不对，说明游戏已重新下载资源，`restore` 的备份可能已被覆盖。

**`install` 报「需要 root」？**
`adb root` 失败。雷电/MuMu 等模拟器在设置里开 root；真机需自行解决。

**脚本拒绝写入 `emulator-5554`？**
原版把 5554 当生产实例保护。确认那是你的测试模拟器后加 `--force`。

## 已知限制

- **角色名仍是英文**：`UnitMaster` 这张表只要文件长度变化，进「伙伴」界面就黑屏。已排除加密方式、改动量、msgpack 结构，线索指向文件偏移 446656 处 16 字节未知数据（疑似校验）。因此不含在补丁内。
- **伙伴界面部分标签仍是英文**：`Friend List`、`一键保护`、`告别` 等，来源未定位。
- **任务卡片背景**：国际服原生设计，国服无对应资源，无法贴图替换。

## 兼容性

补丁按 1.58.0 制作。更新游戏大版本后资源包哈希会变，需重新适配。

`install` 会检查设备上的 `versionName`，与 `payload/meta.json` 里的 `game_version` 不符时给出警告。
