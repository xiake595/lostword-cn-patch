#!/system/bin/sh
PKG=jp.goodsmile.touhoulostwordglobal_android
BASE=/sdcard/Android/data/$PKG/files
CACHE=/data/data/$PKG/files/cache
echo "[1/3] 复制剧情/UI/字体 ..."
mkdir -p $BASE/UnityCache/Shared
cp -rf /sdcard/tmp_lw/bundles/. $BASE/UnityCache/Shared/
echo "[2/3] 复制主数据表 ..."
mkdir -p $CACHE
cp -f /sdcard/tmp_lw/master/* $CACHE/
echo "[3/3] 修正属主 ..."
UIDX=$(stat -c %u /data/data/$PKG/files)
chown $UIDX:$UIDX $CACHE/* 2>/dev/null
chmod 600 $CACHE/* 2>/dev/null
echo DONE
