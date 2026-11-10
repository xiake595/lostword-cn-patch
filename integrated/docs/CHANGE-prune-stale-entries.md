# 改动说明：安装器新增「按清单清理旧条目」（ci2）

> 版本标记：`v1.4-20261110b+ci2`　产物：`out\TLW-global-1.58.0-cn-fps-v14c2.apk`（592,186,840 B）
> SHA-256 `555FD7D456B1CB4F666809DAB13ABB7FE5C3B15CBC12D8722A54EAA068A1112F`
> 动机：v1.3(84 张表) → v1.4(70 张表) 时旧表残留，导致商店面板 NullReferenceException 黑屏。

---

## 一、改了什么（`src/tlw/cn/CnSetupActivity.java`）

### 1. 新增两个清单文件

```
files/tlw_cn/installed.list      每行一个主表文件名（70 行）
files/tlw_cn/installed.bundles   每行一个 "A/B"（345 行）
```

每次安装成功后写入，记录**这次安装到底写了哪些文件**。

### 2. 新增 `pruneStale()`：安装后、写 marker 前，清掉「上次写过、这次数据包里没有」的条目

```java
final int prunedMaster  = pruneStale(new File(cnDir, LIST_MASTER),  nowMaster,  ...);
final int prunedBundles = pruneStale(new File(cnDir, LIST_BUNDLE),  nowBundles, ...);
writeNameList(new File(cnDir, LIST_MASTER),  nowMaster);
writeNameList(new File(cnDir, LIST_BUNDLE),  nowBundles);
writeMarkerAtomic(marker, version);        // marker 最后写，保证「清理完成」才标记成功
```

**只删清单里出现过的**——游戏自己下载的表一律不碰。资源包同理，且只有目录空了才删目录。

### 3. 日志新增两个字段

```
extract done: entries=416 seen=761 master=70 bundles=345 cacheInfo=345
              packagedInfo=345 prunedMaster=14 prunedBundles=0 bytes=... version=...
```

## 二、实测（MuMu `127.0.0.1:7555`）

### 模拟「v1.3 残留」场景

1. 把 v1.3 被砍掉的 14 张表塞回 `files/cache`
2. 写一份 84 行的 `installed.list`（模拟上次装的是 v1.3）
3. 删 marker 强制重装

### 结果

```
23:39:40.124 I TlwCn : pruned stale entry: 122128a11474bf37c7d776be4d192d66
23:39:40.124 I TlwCn : pruned stale entry: 19932e1fedb57097193b60498d72b158
23:39:40.124 I TlwCn : pruned stale entry: 1bdec828a74cdded0f365cd25b4a346a
23:39:40.125 I TlwCn : pruned stale entry: 2075fff9609572132f5607c3bdde0277
23:39:40.125 I TlwCn : pruned stale entry: 266ece11033ebd73a275ab7a8d4a0663
23:39:40.125 I TlwCn : pruned stale entry: 4c6c82a379efc3a6900021cb359ab194
23:39:40.125 I TlwCn : pruned stale entry: 6d7c73da9f77e827b76d4bf384bb509b
23:39:40.125 I TlwCn : pruned stale entry: 7010a0a2674fb222a58d5efb6783c292
23:39:40.125 I TlwCn : pruned stale entry: 91cd32aefcadf9f5bdc34fe51eef1411
23:39:40.125 I TlwCn : pruned stale entry: c233ef1d98037e438f8f24a318506a67
23:39:40.125 I TlwCn : pruned stale entry: e62a5ee6cffce97291ab789ab01473b4
23:39:40.125 I TlwCn : pruned stale entry: eafcfa27c264287176ad6e85b9e1bc75
23:39:40.125 I TlwCn : pruned stale entry: fe1811d1cb58fbd771b8cdd467b87ce3
23:39:40.125 I TlwCn : pruned stale entry: manifest.json
23:39:40.125 I TlwCn : pruned stale entries: master=14 bundles=0
23:39:40.128 I TlwCn : extract done: ... prunedMaster=14 prunedBundles=0 ... elapsedMs=4218
```

`files/cache` 从 1250 → **1236**（正好少 14 个），`installed.list` 从 84 行 → **70 行**。

### 商店验证

进游戏 → 下载 59.7 MB（因为删了 14 张表）→ 大厅 → 商店：**正常打开，0 exception**。
游戏自己把 5 张商店表下回来了，全是 1.58 官方版（176,048 / 1,440 / 986,288 …），
界面标题变成 `Shop`（英文），符合 v1.4「商店不汉化」的设计。

## 三、边界情况

| 情况 | 行为 |
|---|---|
| 首次安装（没有清单） | `readNameList` 返回空 → 不删任何东西 → 正常安装 |
| 清单读不到（权限/损坏） | 记 warning，跳过清理，继续安装（不阻断） |
| 删除失败（文件被占用） | 记 warning，继续；最多留旧数据，不会中断安装 |
| 游戏自己下的表 | **不在清单里 → 绝不删** |
| 资源包目录 | 只删 `__data`/`__info`，目录空了才删目录 |

## 四、已知限制

1. **老版本升级第一次仍会有残留**：如果设备上装的是 ci1 或更早（没有清单文件），
   第一次升级到 ci2 时清单是空的 → 那批旧表**这次不会被清**。
   需要**再启动一次**（第二次走 `pruneStale` 就有清单了）才会清。
   或者手动删一次（见 TROUBLESHOOT 文档）。
2. 清单是「自己写过的」快照，不校验文件内容是否被游戏覆盖过。
   如果游戏覆盖了某个表（比如商店表被重下成官方版），下次升级时该表若已不在数据包内，
   仍会被删掉 —— 这符合预期（旧汉化表本来就不该留）。
