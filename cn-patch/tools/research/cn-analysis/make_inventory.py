# -*- coding: utf-8 -*-
"""Build cn_data_inventory.json + verify payload integrity against inner manifest."""
import hashlib
import json
import os
import zipfile

ZIP = r'D:\Codex_Project\Lostword\work\lwlocal.zip'
REPO_MANIFEST = r'D:\Codex_Project\Lostword\work\cn-patch\manifest.json'
OUT = r'D:\Codex_Project\Lostword\integrated\docs\cn_data_inventory.json'

z = zipfile.ZipFile(ZIP)
infos = z.infolist()
names = [i.filename for i in infos]
prefix = 'lwlocal/'

bundle_entries = [i for i in infos if i.filename.startswith(prefix + 'bundles/')]
master_entries = [i for i in infos if i.filename.startswith(prefix + 'master/')]
root_files = [i for i in infos if i.filename[len(prefix):].count('/') == 0]


def entry_meta(i):
    rel = i.filename[len(prefix):]
    return {
        'path': rel,
        'size': i.file_size,
        'sha256': hashlib.sha256(z.read(i.filename)).hexdigest(),
        'crc32': format(i.CRC, '08x'),
    }


def sha256_of_zip_entry(name):
    h = hashlib.sha256()
    n = 0
    with z.open(name) as f:
        while True:
            b = f.read(4 * 1024 * 1024)
            if not b:
                break
            h.update(b)
            n += len(b)
    return h.hexdigest(), n


# ---- totals ----
total_uncompressed = sum(i.file_size for i in infos)
total_compressed = sum(i.compress_size for i in infos)
zip_bytes = os.path.getsize(ZIP)
zh = hashlib.sha256()
with open(ZIP, 'rb') as f:
    while True:
        b = f.read(8 * 1024 * 1024)
        if not b:
            break
        zh.update(b)
zip_sha256 = zh.hexdigest()

# ---- bundle directories ----
bundle_dirs = {}
for i in bundle_entries:
    rel = i.filename[len(prefix + 'bundles/'):]
    a, b, leaf = rel.split('/')
    bundle_dirs.setdefault((a, b), []).append(rel)

repo = json.load(open(REPO_MANIFEST, encoding='utf-8'))
manifest_bundles = repo['bundles']
extra_a = sorted(set(a for a, _ in bundle_dirs) - set(manifest_bundles.keys()))
missing_a = sorted(set(manifest_bundles.keys()) - set(a for a, _ in bundle_dirs))

# ---- inner master manifest (list of {table,file,applied,missing,size}) ----
inner_manifest_name = prefix + 'master/manifest.json'
inner_manifest = json.loads(z.read(inner_manifest_name).decode('utf-8'))
inner_by_file = {e['file']: e for e in inner_manifest}
master_data_entries = [i for i in master_entries if not i.filename.endswith('/manifest.json')]

# verify sizes
size_mismatch = []
for i in master_data_entries:
    fname = i.filename.rsplit('/', 1)[1]
    e = inner_by_file.get(fname)
    if e and e.get('size') not in (None, i.file_size):
        size_mismatch.append({'file': fname, 'zip': i.file_size, 'manifest': e['size']})
master_not_in_inner = sorted(set(i.filename.rsplit('/', 1)[1] for i in master_data_entries) - set(inner_by_file))
inner_not_in_zip = sorted(set(inner_by_file) - set(i.filename.rsplit('/', 1)[1] for i in master_data_entries))

# ---- samples: 3 master + 3 bundles, deterministic (first N sorted) ----
master_sample_names = sorted(i.filename for i in master_data_entries)[:3]
bundle_sample_names = sorted(i.filename for i in bundle_entries)[:3]
samples = []
for n in master_sample_names + bundle_sample_names:
    h, sz = sha256_of_zip_entry(n)
    samples.append({'zip_entry': n, 'size': sz, 'sha256': h,
                    'install_as': n[len(prefix):]})

# ---- version strings ----
inner_version_raw = z.read(prefix + 'version.txt')
release_version_file = r'D:\Codex_Project\Lostword\work\version.txt'
release_version = open(release_version_file, 'rb').read() if os.path.exists(release_version_file) else b''

# ---- per-category bytes ----
bundle_bytes = sum(i.file_size for i in bundle_entries)
master_bytes = sum(i.file_size for i in master_entries)
root_bytes = sum(i.file_size for i in root_files)

inventory = {
    'schema': 1,
    'generated_by': 'cn-analyst (task-1)',
    'generated_at': '2026-11-09T15:30:00+08:00',
    'source': {
        'zip': 'work/lwlocal.zip',
        'zip_url': 'https://github.com/xiake595/lostword-cn-patch/releases/download/v1.3/lwlocal.zip',
        'zip_bytes': zip_bytes,
        'zip_sha256': zip_sha256,
        'repo_manifest': 'work/cn-patch/manifest.json',
        'module_apk': 'work/LwLocal-1.3.apk (package lw.mod, entry lw.mod.LwLocalHook)',
        'game': {
            'package': repo['game_package'],
            'version_name': repo['game_version'],
            'version_code': repo['version_code'],
        },
    },
    'version_strings': {
        'release_asset_version_txt': release_version.decode('utf-8', 'replace').strip(),
        'zip_inner_lwlocal_version_txt': inner_version_raw.decode('utf-8', 'replace').strip(),
        'zip_inner_version_txt_raw_hex': inner_version_raw.hex(),
        'note': 'zip 内 version.txt 是滞后元数据(v1.1-20261108)，真实数据版本以 Release 的独立 version.txt 为准；模块只跳过该条目，不校验内容',
    },
    'totals': {
        'zip_entries': len(infos),
        'installed_files': len(infos) - 1,  # version.txt is skipped by installer
        'total_uncompressed_bytes': total_uncompressed,
        'total_compressed_bytes': total_compressed,
        'zip_bytes': zip_bytes,
        'all_stored': all(i.compress_type == zipfile.ZIP_STORED for i in infos),
        'bundle_files': len(bundle_entries),
        'bundle_dir_count_A': len(set(a for a, _ in bundle_dirs)),
        'bundle_bytes': bundle_bytes,
        'master_entries': len(master_entries),
        'master_data_tables': len(master_data_entries),
        'master_bytes': master_bytes,
        'root_entries': len(root_files),
        'root_bytes': root_bytes,
        'expected_files_after_install': {
            'filesDir_cache': len(master_entries),  # module写 master/ 下全部(含 manifest.json)
            'external_UnityCache_Shared': len(bundle_entries),
            'note': '官方模块 unzip 把 lwlocal/master/* (含 manifest.json, 84 项) 写入 files/cache/，把 345 个 __data 写入 UnityCache/Shared/<A>/<B>/',
        },
    },
    'bundle_manifest_crosscheck': {
        'manifest_bundle_count': len(manifest_bundles),
        'zip_bundle_A_dirs': len(set(a for a, _ in bundle_dirs)),
        'extra_A_dirs_not_in_repo_manifest': extra_a,
        'missing_A_dirs_in_zip': missing_a,
        'extra_dir_details': [
            {'A': a,
             'B': bundle_dirs[(a, [bb for aa, bb in bundle_dirs if aa == a][0])][0].split('/')[1] if False else None}
            for a in []  # filled below
        ],
    },
    'master_crosscheck': {
        'inner_manifest_entries': len(inner_manifest),
        'zip_master_data_tables': len(master_data_entries),
        'size_mismatch': size_mismatch,
        'zip_master_not_in_inner_manifest': master_not_in_inner,
        'inner_manifest_not_in_zip': inner_not_in_zip,
    },
    'samples_sha256': samples,
    'install_map': {
        'bundle': 'lwlocal/bundles/<A>/<B>/__data -> <externalFilesDir>/UnityCache/Shared/<A>/<B>/__data',
        'master': 'lwlocal/master/<file> -> <filesDir>/cache/<file>  (官方模块写入全部 84 项，含 manifest.json)',
        'version_txt': '跳过（模块 unzip 里 if !name.endsWith("version.txt")）',
    },
}

# fill extra dir details with parse results (if available)
extra_details = []
try:
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from parse_bundles import parse_header
    for a in extra_a:
        b = [bb for aa, bb in bundle_dirs if aa == a][0]
        entry = f'lwlocal/bundles/{a}/{b}/__data'
        info = parse_header(z.read(entry), verbose=False)
        extra_details.append({
            'A': a, 'B': b, 'size': z.getinfo(entry).file_size,
            'asset_paths': [n['path'] for n in info.get('nodes', [])],
        })
except Exception as e:  # noqa
    extra_details = [{'error': repr(e)}]
inventory['bundle_manifest_crosscheck']['extra_dir_details'] = extra_details

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
    json.dump(inventory, f, ensure_ascii=False, indent=2)
print('wrote', OUT)
print(json.dumps({k: inventory[k] for k in
                  ['totals', 'bundle_manifest_crosscheck', 'master_crosscheck',
                   'version_strings']}, ensure_ascii=False, indent=2))
print('extra details:', json.dumps(extra_details, ensure_ascii=False))
