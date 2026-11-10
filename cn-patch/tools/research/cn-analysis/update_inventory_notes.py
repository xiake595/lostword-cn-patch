# -*- coding: utf-8 -*-
import json

P = r'D:\Codex_Project\Lostword\integrated\docs\cn_data_inventory.json'
d = json.load(open(P, encoding='utf-8'))
d['install_map'] = {
    'bundle': 'lwlocal/bundles/<A>/<B>/__data -> <externalFilesDir>/UnityCache/Shared/<A>/<B>/__data',
    'master': 'lwlocal/master/<file> -> <filesDir>/cache/<file>  (官方模块写入全部 84 项: 83 张 hash 表 + manifest.json)',
    'version_txt': '跳过 (官方模块 unzip: !name.endsWith("version.txt"))；zip 内 version.txt 不落盘',
    'no_info': '不创建任何 __info；官方数据包与模块均不写 __info',
}
d['notes'] = [
    'master 84 项 = 83 张 hash 表 + master/manifest.json；repo manifest 的 master_tables 84 条把 manifest.json 也算了一条，勿当作 84 张表。',
    'zip 内 master/manifest.json 自带 81 条条目且有 2 个表未列入、13 个 size 字段与 zip 实际不符 → 不要用 zip 内 manifest 过滤或校验。',
    '345 = 340(repo manifest) + 5 个 v1.1 新增场景包；官方模块不解析任何 manifest，逐条解包全部 430 entries → 安装器必须装全部 345。',
    'JS 内 lwlocal/version.txt = v1.1-20261108 是滞后元数据；Release 独立 version.txt = v1.3-20261109b 才是真实版本；marker 建议用后者或 zip sha256。',
    '官方模块唯一 hook = Application.attach，仅写文件、不 hook 资源加载/下载/缓存校验；首启预置可行性为高置信推断（游戏侧 AssetDownloader.IsCacheValid 走 Caching.IsVersionCached / File.Exists），详见 CN_DATA_SPEC.md §5。',
]
json.dump(d, open(P, 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=2)
print('updated; keys:', list(d.keys()))
