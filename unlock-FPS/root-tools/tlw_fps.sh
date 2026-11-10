#!/system/bin/sh
# ============================================================
# tlw_fps.sh - Touhou LostWord FPS unlock
#
# How it works
#   Unity stores Application.targetFrameRate in libunity.so .data
#   Default is -1 -> falls back to hardcoded 30fps, quantized by vsync
#   165Hz display: 30fps lands on 27.5fps (165/6)
#
# Note
#   Android 15 (MuMu 15) uses 48-bit addresses like 0x400020800000.
#   mksh arithmetic is 32-bit and overflows, so address math uses awk.
#
# Usage
#   sh tlw_fps.sh              # auto detect + set to refresh rate
#   sh tlw_fps.sh 120          # set specific fps (also saved)
#   sh tlw_fps.sh 0            # restore default
#   sh tlw_fps.sh status       # show current value
#   sh tlw_fps.sh daemon       # daemon using saved target
#   sh tlw_fps.sh daemon 120   # daemon with explicit target
#   sh tlw_fps.sh stop         # stop daemon
# ============================================================

DIR=$(dirname "$0")
[ -f "$DIR/tlw_common.sh" ] && . "$DIR/tlw_common.sh"
[ -f /data/local/tmp/tlw_common.sh ] && . /data/local/tmp/tlw_common.sh

OFF_CACHE=/data/local/tmp/tlw_fps_offset.txt
TARGET_FILE=/data/local/tmp/tlw_fps_target.txt
DAEMON_PIDF=/data/local/tmp/tlw_fps_daemon.pid

TARGET=""
MODE="set"
for a in "$@"; do
  case "$a" in
    autodetect|detect) MODE="detect" ;;
    status)     MODE="status" ;;
    daemon)     MODE="daemon" ;;
    stop)       MODE="stop" ;;
    '') ;;
    *[!0-9]*) ;;
    *) TARGET="$a" ;;
  esac
done

PKG=$(detect_pkg)
if [ -z "$PKG" ]; then
  err "game not found"
  exit 1
fi
VER=$(get_version "$PKG")
PKG_CURRENT="$PKG"

# ---------- saved target ----------
save_target() { echo "$1" > "$TARGET_FILE"; }
load_target() {
  if [ -f "$TARGET_FILE" ]; then
    cat "$TARGET_FILE" 2>/dev/null | tr -d '\r\n '
  fi
}

# ---------- offset ----------
get_offset() {
  if [ -f "$OFF_CACHE" ]; then
    CF1=$(cut -d' ' -f1 "$OFF_CACHE" 2>/dev/null | tr -d '\r')
    CF2=$(cut -d' ' -f2 "$OFF_CACHE" 2>/dev/null | tr -d '\r')
    if [ -n "$CF2" ]; then
      case "$CF2" in
        0x*)
          if [ "$CF1" = "$VER" ] || [ "$CF1" = "$PKG" ]; then
            echo "$CF2"
            return 0
          fi
          ;;
      esac
    fi
  fi

  KNOWN=$(fps_offset_for "$PKG" "$VER")
  if [ -n "$KNOWN" ]; then
    echo "$VER $KNOWN" > "$OFF_CACHE"
    echo "$KNOWN"
    return 0
  fi

  err "ver $VER unknown - run the bat on PC to detect offset"
  return 1
}

get_refresh_rate() {
  dumpsys display 2>/dev/null | grep -m1 -o 'fps=[0-9.]*' | head -1 | cut -d= -f2 | cut -d. -f1
}

read_mem4() {
  read_proc_mem "$1" "$2"
}

# ---------- write fps ----------
# return: 0 = wrote, 2 = already correct, 1 = error
write_fps() {
  VAL=$1
  VA_OFF=$(get_offset)
  [ -z "$VA_OFF" ] && return 1

  PID=$(pidof "$PKG" 2>/dev/null)
  [ -z "$PID" ] && return 1

  BASE=$(get_libunity_base "$PKG")
  [ -z "$BASE" ] && return 1

  OFF_HEX=$(echo "$VA_OFF" | sed 's/^0x//')
  ADDR=$(hex_add "$BASE" "$OFF_HEX")
  if [ -z "$ADDR" ] || [ "$ADDR" = "0" ]; then
    return 1
  fi

  B0=$((VAL & 255)); B1=$(((VAL >> 8) & 255))
  B2=$(((VAL >> 16) & 255)); B3=$(((VAL >> 24) & 255))
  printf "\\$(printf '%03o' $B0)\\$(printf '%03o' $B1)\\$(printf '%03o' $B2)\\$(printf '%03o' $B3)" \
    > /data/local/tmp/tlw_fps.bin

  CUR=$(read_mem4 "$PID" "$ADDR")
  WANT=$(od -An -tx1 /data/local/tmp/tlw_fps.bin | tr -d ' \n')
  [ -z "$CUR" ] && return 1
  [ "$CUR" = "$WANT" ] && return 2

  if write_proc_mem "$PID" "$ADDR" /data/local/tmp/tlw_fps.bin; then
    return 0
  fi
  return 1
}

# ---------- main ----------
case "$MODE" in

  detect)
    info "pkg: $PKG"
    info "ver: $VER"
    OFF=$(get_offset)
    if [ -n "$OFF" ]; then
      ok "offset: $OFF"
    else
      err "detect failed"
      exit 1
    fi
    ;;

  status)
    OFF=$(get_offset)
    [ -z "$OFF" ] && { err "offset unknown"; exit 1; }
    PID=$(pidof "$PKG" 2>/dev/null)
    [ -z "$PID" ] && { err "game not running"; exit 1; }
    BASE=$(get_libunity_base "$PKG")
    [ -z "$BASE" ] && { err "libunity.so not loaded"; exit 1; }
    OFF_HEX=$(echo "$OFF" | sed 's/^0x//')
    ADDR=$(hex_add "$BASE" "$OFF_HEX")
    RAW=$(read_mem4 "$PID" "$ADDR")
    echo "pkg       : $PKG"
    echo "ver       : $VER"
    echo "offset    : $OFF"
    echo "libunity  : 0x$BASE"
    echo "addr      : $ADDR"
    echo "raw bytes : $RAW"
    if [ -z "$RAW" ]; then
      echo "status    : READ FAILED"
    else
      VAL=$(hex_to_int "$RAW")
      echo "fps value : $VAL"
      if [ "$VAL" = "-1" ] || [ "$VAL" = "0" ]; then
        echo "status    : follow display"
      else
        echo "status    : locked at $VAL fps"
      fi
    fi
    SAVED=$(load_target)
    [ -n "$SAVED" ] && echo "saved     : $SAVED"
    ;;

  daemon)
    if [ -z "$TARGET" ]; then
      TARGET=$(load_target)
      if [ -n "$TARGET" ]; then
        info "daemon using saved target: ${TARGET}fps"
      else
        TARGET=$(get_refresh_rate)
        [ -z "$TARGET" ] && TARGET=60
        info "daemon using refresh rate: ${TARGET}fps"
      fi
    else
      info "daemon using explicit target: ${TARGET}fps"
    fi

    save_target "$TARGET"

    if [ -f "$DAEMON_PIDF" ]; then
      OLD=$(cat "$DAEMON_PIDF" 2>/dev/null)
      [ -n "$OLD" ] && kill -9 "$OLD" 2>/dev/null
    fi
    echo $$ > "$DAEMON_PIDF"

    LAST=""
    FIXES=0
    while true; do
      PID=$(pidof "$PKG" 2>/dev/null)
      if [ -n "$PID" ] && [ "$PID" != "$LAST" ]; then
        echo "[$(date +%H:%M:%S)] attached pid=$PID"
        LAST="$PID"
      fi
      if [ -n "$PID" ]; then
        write_fps "$TARGET"
        RC=$?
        if [ "$RC" = "0" ]; then
          FIXES=$((FIXES + 1))
          echo "[$(date +%H:%M:%S)] re-applied ${TARGET}fps (fix #$FIXES)"
        fi
      fi
      sleep 1
    done
    ;;

  stop)
    if [ -f "$DAEMON_PIDF" ]; then
      OLD=$(cat "$DAEMON_PIDF" 2>/dev/null)
      [ -n "$OLD" ] && kill -9 "$OLD" 2>/dev/null
      rm -f "$DAEMON_PIDF"
    fi
    pkill -f "tlw_fps.sh daemon" 2>/dev/null
    ok "daemon stopped"
    ;;

  set)
    if [ -z "$TARGET" ]; then
      TARGET=$(get_refresh_rate)
      [ -z "$TARGET" ] && TARGET=60
      info "no fps given, using refresh rate: ${TARGET}fps"
    fi
    save_target "$TARGET"
    write_fps "$TARGET"
    RC=$?
    case "$RC" in
      0) ok "applied ${TARGET}fps  (saved)" ;;
      2) ok "already ${TARGET}fps  (saved)" ;;
      *) err "write failed" ;;
    esac

    # A running daemon keeps its own copy of TARGET in memory and would keep
    # forcing the old value back every second. Restart it with the new target.
    GUARD=""
    for g in "$(dirname "$0")/tlw_guard.sh" /data/local/tmp/tlw_guard.sh; do
      [ -f "$g" ] && { GUARD="$g"; break; }
    done

    WAS_RUNNING=""
    if [ -f "$DAEMON_PIDF" ]; then
      OLD=$(cat "$DAEMON_PIDF" 2>/dev/null)
      if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
        WAS_RUNNING="1"
      fi
    fi
    # also detect by process scan (pidfile can be stale)
    if [ -z "$WAS_RUNNING" ]; then
      for pr in /proc/[0-9]*; do
        if [ -r "$pr/cmdline" ]; then
          cc=$(tr '\0' ' ' < "$pr/cmdline" 2>/dev/null)
          case "$cc" in
            *tlw_fps.sh\ daemon*) WAS_RUNNING="1" ;;
          esac
        fi
      done
    fi

    if [ -n "$WAS_RUNNING" ] && [ -n "$GUARD" ]; then
      case "$TARGET" in
        0|-1)
          # 0 / -1 means "follow display" - the guard has nothing to enforce,
          # so stop it instead of restarting with a zero target.
          info "target is follow-display, stopping daemon"
          sh "$GUARD" stop >/dev/null 2>&1
          ;;
        *)
          info "restarting daemon with new target"
          sh "$GUARD" start "$TARGET" >/dev/null 2>&1
          ;;
      esac
    fi
    ;;

esac
