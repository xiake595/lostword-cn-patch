#!/system/bin/sh
# ============================================================
# tlw_guard_loop.sh —— 后台守护：UnityCache 被清空就自动回填
#
# 自动探测包名和应用 UID，兼容国际服/国服、多开环境
# 每 2 秒检查一次，发现 UnityCache 变小就立刻用备份替换
# ============================================================

DIR=$(dirname "$0")
[ -f "$DIR/tlw_common.sh" ] && . "$DIR/tlw_common.sh"
[ -f /data/local/tmp/tlw_common.sh ] && . /data/local/tmp/tlw_common.sh

THRESHOLD_KB=102400
LOG=/data/local/tmp/tlw_guard.log

PKG=$(detect_pkg)
if [ -z "$PKG" ]; then
  echo "[$(date +%H:%M:%S)] [x] game package not found, exit"
  exit 1
fi

D=/data/data/$PKG
E=/sdcard/Android/data/$PKG
CACHE="$E/files/UnityCache"
BAK="$E/files/UnityCache.bak"

size_kb()    { du -sk "$1" 2>/dev/null | cut -f1; }
dirs_count() { ls "$1/Shared" 2>/dev/null | wc -l; }

# 动态取 UID/GID，不硬编码
APP_UID=$(stat -c%u "$D" 2>/dev/null)
[ -z "$APP_UID" ] && APP_UID=0
EXT_GID=$(stat -c%g "$E/files" 2>/dev/null)
[ -z "$EXT_GID" ] && EXT_GID=1078

BSZ=$(size_kb "$BAK")
if [ -z "$BSZ" ] || [ "$BSZ" -lt "$THRESHOLD_KB" ]; then
  echo "[$(date +%H:%M:%S)] [x] backup unavailable (${BSZ:-0}KB), guard exit"
  exit 1
fi

echo "[$(date +%H:%M:%S)] guard start  pkg=$PKG  uid=$APP_UID gid=$EXT_GID"
echo "[$(date +%H:%M:%S)] backup=${BSZ}KB/$(dirs_count "$BAK")dirs  threshold=${THRESHOLD_KB}KB"

RESTORED=0

while true; do
  SZ=$(size_kb "$CACHE")
  [ -z "$SZ" ] && SZ=0

  if [ "$SZ" -lt "$THRESHOLD_KB" ] && [ "$RESTORED" -eq 0 ]; then
    echo "[$(date +%H:%M:%S)] wipe detected ${SZ}KB -> restoring"
    rm -rf "$CACHE"
    if ! cp -a "$BAK" "$CACHE" 2>/dev/null; then
      echo "[$(date +%H:%M:%S)] cp -a failed, retry cp -r"
      rm -rf "$CACHE"
      cp -r "$BAK" "$CACHE" 2>/dev/null
    fi
    chown -R "$APP_UID:$EXT_GID" "$CACHE" 2>/dev/null
    chmod -R 771 "$CACHE" 2>/dev/null
    echo "[$(date +%H:%M:%S)] restore done $(size_kb "$CACHE")KB/$(dirs_count "$CACHE")dirs"
    echo "[$(date +%H:%M:%S)] >>> Click CANCEL now, NOT Confirm <<<"
    RESTORED=1
  fi

  sleep 2
done
