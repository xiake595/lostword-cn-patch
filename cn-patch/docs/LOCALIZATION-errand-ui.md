# 派遣（Errand）界面汉化源定位与替换思路

> 结论报告（不执行替换）。日期：2026-11-09。对象：国际服 1.57.0 + 汉化补丁 v1.3 + 整合包 v4。
> 证据数据：官方设备 `<DEVICE_SERIAL>`（PA2473 / Android 16 / 官方包 + 完整缓存）拉取的
> `UnityCache/Shared` 共 **6,697 个 bundle / 2.75 GB**，解包到 `work\dev-cache\`（约 5.1 GB）。

---

## 0. 先回答：UI 汉化到底在哪一层？

**界面上的固定文字主要在「资源包内 UI 预制体的文本字段」里，不在加密主表，也不是图片。**
已经用官方完整缓存逐包验证（6,697 个包全部解压扫描，0 失败），分三层：

| 层 | 存放位置 | 装什么 | 本次派遣界面的例子 |
|---|---|---|---|
| **资源包文本** | `UnityCache/Shared/<A>/<B>/__data` 内 UI 预制体（MonoBehaviour `LocalizeText`，字段 `m_Text` / `enText` / `jpText`） | 界面固定文案 | `Completed Errands`、`Remaining:`、`Cost`、`There are no Limited Errands available.` |
| **加密主表** | 应用内部 `files/cache/`（84 张表，EAST 类格式，熵 ≈ 8.0，非 zlib/lzma/lz4/brotli 头） | 运行时拼的动态内容 | 角色名、技能名/说明、道具名、任务名/说明、章节名等 |
| **图片（Sprite/Texture）** | 资源包里的 SpriteAtlas / Texture2D | 少数固定图形 | `Exp` 图标、`每日/临时` 按钮图、`一键完成(Complete All)` 按钮图、`Exchange` / `Errand` 主界面按钮 |

判断依据（关键证据）：
- 在 6,697 个官方 bundle 全部解压后的数据里搜 `Complete All` → **0 命中**，而官方截图里明明显示
  `Complete All` ⇒ 它是**图片**（`68be5064…` 精灵图集里的按钮图），不是文本。
- `Completed Errands` → 命中 **1 个包**，是 MonoBehaviour `LocalizeText` 的 `m_Text/enText` 字段
  （见下表）⇒ 是文本，但所在 bundle **不在汉化补丁的 345 个包里**，所以保持英文。
- 补丁自己翻译的界面文案也写在 bundle 文本字段里（如 `a58687fb…` 里
  `HomeBackgroundRepeatDialog/.../TimeText` = `所需时间`；`3066f5fe…` 里 `必要時間`→`必要时间`）。
- Il2CppDumper 的 13,668 条字符串字面量里搜不到这些 UI 文案 ⇒ 不是 C# 代码写死的。

> 关于 REA：本会话没有注册 REA 的 MCP 工具（`rea_*` 一个都不存在，Android 侧
> `inspect_android_package` 不可用），本报告用等价的静态逆向流程完成：
> Il2CppDumper 产物（`work\cn-analysis\il2cpp-out\`）+ 自写 UnityFS 解析器（LZ4 块解压、
> 处理 `0x80` 尾部 blocks-info / `0x200` 对齐）+ UnityPy 1.25.4 读 SerializedFile/MonoBehaviour
> typetree。结论与 REA 的 metadata 检查一致（非硬编码字符串）。

---

## 1. 派遣界面文案的精确位置

### 1.1 主预制体包（关键缺失包）

| 项 | 值 |
|---|---|
| 缓存键 | `218d248860d4e311e25b70b6497334d4` / `5833fefffd29a78acc4f52e91fcb2ece` |
| 官方 `__data` | 152,132 B（`work\dev-cache\218d2488…\5833fe…\__data`） |
| 解压后 | 529,020 B；6,741 个对象；脚本类含 `ErrandBehaviour` / `ErrandCell` / `ErrandPage` / `ErrandResultPopup` |
| 根节点 | `UI/Canvas/UIPanel/Root/Errand`（另有 `Root/DepertureCount` 计数面板） |
| 汉化补丁 | **不在 345 个包里** ⇒ 这是派遣界面仍英文的直接原因 |

包内 `LocalizeText` 组件（字段：`m_Text` / `enText` / `jpText`，`showingLanguage=1` 时按英文模式读取 `enText`）
中尚未汉化的条目：

| 文案（EN） | 对象路径 | 字段值 | 说明 |
|---|---|---|---|
| `Completed Errands` | `UI/Canvas/UIPanel/Root/DepertureCount/CanvasGroup/LeftBottom/Text` | `m_Text`=`enText`=`Completed Errands`，`jpText`=`おつかい完了数`，`isFixedText=1` | 就是截图左下「Completed Errands 0/3」 |
| `Remaining:` | `…/Root/Errand/CanvasGroup/Daily/List/Contents/cell/Frame/AppearTime/Text` | `enText`=`Remaining:`，`jpText`=`出現時間` | 临时派遣的出现时间标签 |
| `Cost` | `…/Daily/List/Contents/cell/Mask/Details/ConsumePhantasmPoint/Text` | `enText`=`Cost`，`jpText`=`消費` | 消耗灵P标签 |
| `There are no Limited Errands available.` | `…/Daily/Empty/Text` | `enText`=该句，`jpText`=`臨時のおつかいは発生していません` | 临时页空态文案 |

同包内另有纯 `Text` 组件（无 `enText` 字段，运行时由 ErrandCell 赋值），例如
`？？式、？？式\n？？式、？？式`、`仲間？人以上`、`Lv<color="#FF8C00">1</color>…`，
这些是占位符/格式串，不需要翻译；实际显示值走主表/运行时格式。

### 1.2 图片类文案（派遣界面）

| 文案 | 类型 | 位置 | 汉化补丁状态 |
|---|---|---|---|
| `Exp`（绿色箭头图标上的字） | Sprite | `68be50648b14ed216c41d4e291a9aef3/3c1e0faf251763b56b30a2ccd2de4027` → Sprite `Errand_Icon_Exp`（同一图集含 `errand_btn_daily`/`errand_btn_limited`/`Errand_btn_bundle` 等 45 个 Sprite） | **补丁包含该 CN 版 bundle**；但 CN 素材本身仍是 `Exp` 英文，图片无法用文本替换 |
| `每日` / `临时` 按钮 | Sprite | 同上：`errand_btn_daily` / `errand_btn_limited` | 补丁 CN 版已是中文（截图已显示） |
| `一键完成`（原 `Complete All`） | Sprite（全部 6,697 包解压文本 0 命中） | 同上图集（`Errand_btn_bundle` 等按钮图） | 补丁 CN 版已是中文 |

### 1.3 已覆盖/其他相关包（说明为什么大部分是中文）

| 缓存键（A） | 官方大小 | 在补丁 345 包 | 与派遣界面的关系 |
|---|---|---|---|
| `058ca74…` | 530,444 | ✅ | ErrandCount 计数面板；CN 版含 `派遣次数` / `Total Errands` / `おつかい回数` |
| `68be5064…` | 603,804 | ✅ | 派遣精灵图集（每日/临时/一键完成/Exp 图标） |
| `a58687fb…` | 4,217,258 | ✅ | 含 `HomeBackgroundRepeatDialog`，补丁已译 `所需时间`/`剩余时间` |
| `4b138761…` | 1,256,954 | ✅ | 重复战斗等共用弹窗，补丁已译 |
| `3066f5fe…` | 1,299,446 | ✅ | 训练室等共用弹窗，补丁已译 `必要時間`→`必要时间` |
| `16b3458c…` | 179,308 | ❌ | 个人资料页 `ErrandCountText`=`Errands` / `Total Errands` 等 |
| `4b2fe288…` | 180,636 | ❌ | 个人资料页 `Total Errands` |
| `8df5deee…` / `c9e335d2…` / `ab27164e…` / `dfb53e68…` | 0.16–0.94 MB | ❌ | 其他 `Total Errands` / `Time Required` 变体 |
| `ee65f601…` | 837,478 | ❌ | 派遣结果页 `ErrandResultUnitPage` |
| `e862eb60…` | 48,475 | ❌ | 主界面 `ErrandButton` / `ErrandBadge` / `ErrandExButton` |
| `f7d6121b…` | 441,344 | ❌ | `DispatchEnd`（派遣结束） |

> `Time Required` 文本在官方缓存里共 4 个包（`3066f5fe…`、`4b138761…`、`dfb53e68…`、
> `a58687fb…`），均属重复战斗/训练室等面板；派遣行里的「剩余时间」在补丁后已显示中文，
> 说明该位置走的是 CN 主表/运行时文本，不在本次缺失的 bundle 里。

---

## 2. 为什么会出现「覆盖效果不佳」

1. **补丁只覆盖 345 个 bundle**，是按缓存键逐个替换的「有国服对应资源的子集」。
   派遣界面的主预制体 `218d2488…` 不在其中（国服该界面资源缺失/版本不同），
   于是它内部 `LocalizeText` 的英文原文（`enText`）被原样显示。
2. **图片类文案**（`Complete All` / `Exp` / 按钮图）本来就无法用文本替换；其中
   `Complete All`、`每日/临时` 国服素材已有中文，`Exp` 国服素材也是 `Exp`。
3. 同一界面里「文本+图片+主表」混排，所以补丁后会出现「部分中文、部分英文」的观感。

---

## 3. 替换思路（报告，不执行）

### 方案 A（推荐，改动最小）：直接修 `218d2488…` 这个预制体包的文本字段

前提：拿不到国服对应 bundle（现状），就用**官方 bundle + 本地改文本**的方式做「合成 CN 版」。

1. 取包：`work\dev-cache\218d248860d4e311e25b70b6497334d4\5833fefffd29a78acc4f52e91fcb2ece\__data`（152,132 B）。
2. `UnityPy.load(path)` → 遍历 `MonoBehaviour`，筛选 `m_Script` 指向的
   `MonoScript.m_ClassName == 'LocalizeText'`（typetree 含 `enText` 字段）。
   对目标条目同时修改 **`m_Text` 与 `enText`**（补丁 v1.1 经验：英文模式实际读 `enText`，
   只改 `m_Text` 会不生效），`jpText` 保留不动。
   建议译法（可按整合包统一用语调整）：
   - `Completed Errands` → `已完成派遣`
   - `Remaining:` → `剩余：`
   - `Cost` → `消耗`
   - `There are no Limited Errands available.` → `暂无可用的临时派遣`
3. `env.save()` 重新打包（UnityPy 会重算 serialized 偏移与块压缩，**不要**做字节级等长替换，
   长度变化会破坏 SerializedFile 结构）；再用 UnityPy 重载 + 自写 UnityFS 解析器校验。
4. 加入补丁数据 `integrated\assets\lwlocal.zip`，条目路径必须保持**原缓存键**：
   `lwlocal/bundles/218d248860d4e311e25b70b6497334d4/5833fefffd29a78acc4f52e91fcb2ece/__data`
   （安装器按条目路径落盘并写 `__info`；430 → 431 条）。
5. `assets\tlw_cn.version` 升版本号（如 `v1.3-20261109b+ci2`）触发首启重装；
   `build-cn.ps1` 重打 APK → 安装验证（派遣界面应显示 `已完成派遣 0/3`）。
6. 风险与注意：
   - 缓存键（A/B 目录名）必须是游戏实际请求的值；**内容可以不同**，游戏不会校验内容哈希
     （`__info` 里只有 mtime）。我们安装器写 `__info` 的机制已能保证不被清缓存。
   - 该 bundle 只有 152 KB，重打包成本极低；改完需在真机确认字体（中文 TMP 字体在包里已有，
     截图已能显示中文，说明字形可用）。
   - 若个别标签改后仍英文，说明是运行时从加密主表取的值 → 见方案 C。

### 方案 B：图片类（`Exp`、按钮图）

- `Exp`：`68be5064…` 图集里的 `Errand_Icon_Exp` 是 ETC2 压块纹理。用 UnityPy 读 Sprite/Texture2D，
  把中文「经验」绘入同尺寸/同格式纹理后 `env.save()`；补丁已包含该 CN 版 bundle，只需替换
  对应条目即可（保持同一缓存键）。
- `一键完成`、`每日`、`临时`：国服素材已是中文，**无需处理**。
- 注意 atlas 尺寸/格式（ETC2/4x4 块对齐），否则花屏或加载失败。

### 方案 C：若确认某文案来自加密主表（`files/cache`）

- 主表 84 张：熵 ≈ 8.0，无 zlib/lzma/lz4/brotli 头 → 加密（Ghidra 可继续解 il2cpp 解密逻辑）。
- 这属于「主表汉化工程」，需要解密/重加密工具链；本报告涉及的 `Completed Errands` 等不属于此类
  （已在 bundle 中定位到文本），暂不需要。

### 方案 D：上游/完整版

- 向汉化补丁上游要 `218d2488…` 的国服 bundle（若有），或把按方案 A 生成的「合成 CN 版」并入
  整合包分发；同时可一并补齐 `16b3458c` / `4b2fe288` / `ee65f601` / `e862eb60` 等
  个人资料页、派遣结果页、主界面按钮包。

---

## 4. 复现/取证命令（已可重复运行）

```powershell
# 1) 官方缓存（已验证）：设备 PA2473，Android 16
adb -s <DEVICE_SERIAL> exec-out tar -C "/sdcard/Android/data/jp.goodsmile.touhoulostwordglobal_android/files/UnityCache/Shared" -cf - . > work\dev-cache\shared.tar
tar -xf work\dev-cache\shared.tar -C work\dev-cache

# 2) 全量深度扫描（6697 包，0 失败）：搜 UI 文案
python work\cn-triage\scan_official_deep2.py

# 3) 定位文本字段（需要 UnityPy 1.25.4）
python integrated\tools\re\ui_text_report.py
```

关键输出（本次）：
- `218d2488…/5833fe…` → `{'Completed Errands': 2}`
- `058ca74…`、`16b3458c…`、`4b2fe288…`、`8df5deee…`、`ab27164e…`、`c9e335d2…` → `Total Errands`
- `3066f5fe…`、`4b138761…`、`dfb53e68…`、`a58687fb…` → `Time Required`
- `Complete All` → **0 命中（图片）**

---

## 5. 证据文件索引

| 文件 | 内容 |
|---|---|
| `work\dev-cache\<A>\<B>\__data` | 官方完整缓存（6,697 包，2.75 GB）；`218d2488…` 原包在内 |
| `work\cn-triage\scan_official_deep2.py` / `.log` | 全量解压扫描脚本与结果 |
| `work\cn-triage\report_ui_sources.py`（= `integrated\tools\re\ui_text_report.py`） | 按路径/字段输出 LocalizeText 与补丁覆盖状态 |
| `work\cn-triage\unityfs.py`（= `integrated\tools\re\unityfs_extract.py`） | 纯 Python UnityFS/LZ4 解包器 |
| `work\cn-triage\dump_localize218.py` | 218d2488 包全部 LocalizeText 字段 dump |
| `integrated\assets\lwlocal.zip` | 汉化补丁 345 个 bundle（含 058ca74/68be5064 等） |

---

## 6. 结论一句话

派遣界面的英文遗留是**「缺 218d2488 这个 UI 预制体 bundle」**导致的文本字段未替换（`Completed Errands`
等 4 条），加上 `Exp` 这一张**图片素材**国服也是英文；按方案 A 给该 bundle 的 `LocalizeText`
同时改 `m_Text`/`enText` 并以原缓存键加入 `lwlocal.zip`，即可最小成本修复，不需要动加密主表。
