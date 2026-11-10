#!/system/bin/sh
# ============================================================
# tlw_reroll.sh —— 东方归言录 刷初始号（保留资源）
#
# 适用：国际服 jp.goodsmile.touhoulostwordglobal_android
#      国服   com.gg.touhoulw
# 任意 root 模拟器 / 真机均可，自动探测包名和路径
#
# 用法
#   su -c "sh tlw_reroll.sh check"     # 环境自检（第一次先跑这个）
#   su -c "sh tlw_reroll.sh prep"      # 备份 UnityCache（只需一次）
#   su -c "sh tlw_reroll.sh start"     # 刷号
#   su -c "sh tlw_reroll.sh status"    # 查看状态
#   su -c "sh tlw_reroll.sh restore"   # 手动回填
#   su -c "sh tlw_reroll.sh stop"      # 停守护
# ============================================================

DIR=$(dirname "$0")
[ -f "$DIR/tlw_common.sh" ] && . "$DIR/tlw_common.sh"
[ -f /data/local/tmp/tlw_common.sh ] && . /data/local/tmp/tlw_common.sh

THRESHOLD_KB=102400   # 小于 100MB 视为缓存被清空
GUARD_LOG=/data/local/tmp/tlw_guard.log

ACTION="${1:-check}"

# ---------- 初始化环境变量 ----------
init_env() {
  PKG=$(detect_pkg)
  if [ -z "$PKG" ]; then
    err "game not found - is Touhou LostWord installed?"
    exit 1
  fi
  D=/data/data/$PKG
  E=/sdcard/Android/data/$PKG
  CACHE="$E/files/UnityCache"
  BAK="$E/files/UnityCache.bak"
  VER=$(get_version "$PKG")

  # 动态取应用 UID（不同模拟器/多开环境下不一定是 u0_a53）
  APP_UID=$(stat -c%u "$D" 2>/dev/null)
  [ -z "$APP_UID" ] && APP_UID=$(dumpsys package "$PKG" 2>/dev/null | grep -m1 userId= | sed 's/.*userId=//' | tr -d ' \r')
  [ -z "$APP_UID" ] && APP_UID=0

  # 外部存储的组 ID（ext_data_rw 通常是 1078，但取实际值更稳）
  EXT_GID=$(stat -c%g "$E/files" 2>/dev/null)
  [ -z "$EXT_GID" ] && EXT_GID=1078
}

# ---------- 修复缓存属主（用实际 UID，不用硬编码） ----------
fix_owner() {
  TARGET="$1"
  [ -d "$TARGET" ] || return 0
  chown -R "$APP_UID:$EXT_GID" "$TARGET" 2>/dev/null
  chmod -R 771 "$TARGET" 2>/dev/null
  return 0
}

# du that works on /data/data too (needs su on some devices)
size_kb() {
  _v=$(du -sk "$1" 2>/dev/null | cut -f1)
  if [ -z "$_v" ] || [ "$_v" = "0" ]; then
    if command -v su >/dev/null 2>&1; then
      _v=$(su -c "du -sk '$1' 2>/dev/null | cut -f1" 2>/dev/null)
    fi
  fi
  [ -z "$_v" ] && _v=0
  echo "$_v"
}

dirs_count() {
  _v=$(ls "$1/Shared" 2>/dev/null | wc -l)
  if [ "$_v" = "0" ]; then
    if command -v su >/dev/null 2>&1; then
      _v=$(su -c "ls '$1/Shared' 2>/dev/null | wc -l" 2>/dev/null)
    fi
  fi
  [ -z "$_v" ] && _v=0
  echo "$_v"
}

# ---------- 环境自检 ----------
do_check() {
  init_env
  echo "=========================================="
  echo "  Environment Check"
  echo "=========================================="
  echo

  # root
  if check_root; then
    ok "root: OK"
  else
    err "root: NOT available - root required"
    echo "    MuMu: Settings -^> Other -^> enable root"
    echo "    LDPlayer: Settings -^> Other -^> enable root"
    exit 1
  fi

  # 包名
  ok "pkg: $PKG"
  ok "ver: $VER"

  # 数据目录
  if [ -d "$D" ]; then ok "internal data: $D"; else err "internal data missing"; fi
  if [ -d "$E" ]; then ok "external data: $E"; else err "external data missing"; fi

  # 缓存状态
  echo
  CSZ=$(size_kb "$CACHE")
  CDIR=$(dirs_count "$CACHE")
  if [ -z "$CSZ" ]; then CSZ=0; fi
  if [ "$CSZ" -lt "$THRESHOLD_KB" ]; then
    warn "UnityCache: ${CSZ} KB / ${CDIR} dirs  -- incomplete"
    echo "    Launch the game normally and let it download (~646MB)"
  else
    ok "UnityCache: ${CSZ} KB / ${CDIR} dirs"
  fi

  # 备份状态
  BSZ=$(size_kb "$BAK")
  if [ -z "$BSZ" ]; then BSZ=0; fi
  if [ "$BSZ" -lt "$THRESHOLD_KB" ]; then
    warn "backup: none - run prep first"
  else
    ok "backup: ${BSZ} KB / $(dirs_count "$BAK") dirs"
  fi

  # 内部 cache（资源本体）
  ISZ=$(size_kb "$D/files/cache")
  ok "internal: ${ISZ:-0} KB"

  # 帧率偏移
  echo
  OFF=$(fps_offset_for "$PKG" "$VER")
  if [ -n "$OFF" ]; then
    ok "fps offset: $OFF (ver $VER known)"
  else
    warn "fps offset: ver $VER unknown - needs detection"
    echo "    try: sh tlw_fps.sh autodetect"
  fi

  # 游戏进程
  echo
  PID=$(pidof "$PKG" 2>/dev/null)
  if [ -n "$PID" ]; then ok "game pid: $PID"; else info "game not running"; fi

  echo
  echo "=========================================="
}

# ---------- 备份 ----------
do_prep() {
  init_env
  FORCE="$2"

  info "Backing up UnityCache"
  info "app UID: $APP_UID  ext GID: $EXT_GID"

  if [ -d "$BAK" ]; then
    BSZ=$(size_kb "$BAK")
    if [ -n "$BSZ" ] && [ "$BSZ" -gt "$THRESHOLD_KB" ]; then
      if [ "$FORCE" != "force" ]; then
        ok "backup exists: ${BSZ} KB, skipped"
        echo "    to redo after game update: sh $0 prep force"
        exit 0
      fi
      warn "force redo - removing old backup"
      rm -rf "$BAK"
    else
      warn "backup incomplete - redoing"
      rm -rf "$BAK"
    fi
  fi

  SZ=$(size_kb "$CACHE")
  if [ -z "$SZ" ] || [ "$SZ" -lt "$THRESHOLD_KB" ]; then
    err "UnityCache only ${SZ:-0}KB - incomplete"
    echo "    Launch game and let it download fully, then prep"
    exit 1
  fi

  info "current: ${SZ} KB / $(dirs_count "$CACHE") dirs"
  info "copying (~870MB, takes minutes)..."
  if ! cp -a "$CACHE" "$BAK" 2>/dev/null; then
    # FUSE 上 cp -a 可能因无法保留属性而失败，退回普通 cp
    warn "cp -a failed (FUSE), retry with cp -r"
    rm -rf "$BAK"
    cp -r "$CACHE" "$BAK" 2>/dev/null
  fi
  fix_owner "$BAK"

  NEW=$(size_kb "$BAK")
  NEWD=$(dirs_count "$BAK")
  if [ -z "$NEW" ] || [ "$NEW" -lt "$THRESHOLD_KB" ]; then
    err "backup failed (${NEW:-0}KB)"
    echo "    check free space on /sdcard"
    exit 1
  fi
  ok "backup done: ${NEW} KB / ${NEWD} dirs"
}

# ---------- 刷号 ----------
do_start() {
  init_env

  BSZ=$(size_kb "$BAK")
  if [ -z "$BSZ" ] || [ "$BSZ" -lt "$THRESHOLD_KB" ]; then
    err "no usable backup"
    echo "    run first: sh $0 prep"
    exit 1
  fi
  ok "backup OK: ${BSZ} KB"

  info "stopping game"
  am force-stop "$PKG"
  sleep 3

  info "removing account files"
  # /data/data needs root on every emulator we support, so route through su
  # when the direct remove fails.
  wipe_file() {
    _p="$1"
    [ -e "$_p" ] || return 0
    rm -f "$_p" 2>/dev/null
    [ -e "$_p" ] || return 0
    if command -v su >/dev/null 2>&1; then
      su -c "rm -f '$_p'" 2>/dev/null
    fi
    [ -e "$_p" ] || return 0
    return 1
  }

  WIPEFAIL=0
  wipe_file "$D/shared_prefs/io.repro.user.xml" || WIPEFAIL=1
  for _f in "$D/shared_prefs"/io.repro.user.v3.*.xml; do
    [ -e "$_f" ] || continue
    wipe_file "$_f" || WIPEFAIL=1
  done
  wipe_file "$D/files/eastreg.ini" || WIPEFAIL=1
  wipe_file "$D/files/device-id" || WIPEFAIL=1
  wipe_file "$D/files/internal-device-id" || WIPEFAIL=1
  wipe_file "$D/shared_prefs/$PKG.v2.playerprefs.xml" || WIPEFAIL=1

  # analytics SDK keeps the account id in two more places; if they survive the
  # game restores the old account on next launch.
  wipe_file "$D/cache/bugsnag/user-info" || true
  if command -v su >/dev/null 2>&1; then
    su -c "rm -rf '$D/files/io.repro.android/pending_recovery'" 2>/dev/null
  else
    rm -rf "$D/files/io.repro.android/pending_recovery" 2>/dev/null
  fi

  if [ "$WIPEFAIL" = "1" ]; then
    err "account wipe FAILED - files still present (root problem?)"
    echo "    check: adb shell su -c \"ls $D/shared_prefs/io.repro.user.xml\""
    exit 1
  fi
  ok "account wiped"

  info "starting guard"
  pkill -f 'tlw_guard_loop' 2>/dev/null
  # 守护脚本可能在 /data/local/tmp 或与本脚本同目录，两个位置都试
  GUARD=""
  for g in "$DIR/tlw_guard_loop.sh" /data/local/tmp/tlw_guard_loop.sh; do
    if [ -f "$g" ]; then GUARD="$g"; break; fi
  done
  if [ -z "$GUARD" ]; then
    warn "tlw_guard_loop.sh not found - skipping guard"
    warn "if download prompt appears, use menu 5 to restore"
  else
    sh "$GUARD" > "$GUARD_LOG" 2>&1 &
    sleep 1
    ok "guard pid: $!  ($GUARD)"
  fi

  info "launching game"
  am start -n "$PKG/com.google.firebase.MessagingUnityPlayerActivity" >/dev/null 2>&1

  echo
  echo "=========================================="
  echo "  Play the tutorial in game now"
  echo "  At download prompt click CANCEL, not CONFIRM"
  echo "  Then click Game Start to enter"
  echo "=========================================="
}

# ---------- 手动回填 ----------
do_restore() {
  init_env
  BSZ=$(size_kb "$BAK")
  if [ -z "$BSZ" ] || [ "$BSZ" -lt "$THRESHOLD_KB" ]; then
    err "backup unavailable (${BSZ:-0} KB)"
    exit 1
  fi
  info "restoring (backup ${BSZ} KB)..."
  rm -rf "$CACHE"
  if ! cp -a "$BAK" "$CACHE" 2>/dev/null; then
    warn "cp -a failed, retry cp -r"
    rm -rf "$CACHE"
    cp -r "$BAK" "$CACHE" 2>/dev/null
  fi
  fix_owner "$CACHE"
  ok "restore done: $(size_kb "$CACHE") KB / $(dirs_count "$CACHE") dirs"
}

# ---------- 状态 ----------
do_status() {
  init_env
  echo "pkg        : $PKG"
  echo "ver        : $VER"
  echo "UnityCache : $(size_kb "$CACHE") KB / $(dirs_count "$CACHE") dirs"
  echo "backup     : $(size_kb "$BAK") KB / $(dirs_count "$BAK") dirs"
  echo "internal   : $(size_kb "$D/files/cache") KB"
  echo "eastreg    : $(stat -c%s "$D/files/eastreg.ini" 2>/dev/null || echo 0) B"
  echo "game pid   : $(pidof "$PKG" || echo not-running)"
  echo "guard      : $(pgrep -f tlw_guard_loop >/dev/null 2>&1 && echo running || echo stopped)"
}

case "$ACTION" in
  check)   do_check ;;
  prep)    do_prep ;;
  start)   do_start ;;
  restore) do_restore ;;
  status)  do_status ;;
  stop)    pkill -f 'tlw_guard_loop' 2>/dev/null; ok "guard stopped" ;;
  *)       echo "usage: $0 {check|prep|start|restore|status|stop}"; exit 1 ;;
esac
