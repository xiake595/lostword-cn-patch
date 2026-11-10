#!/system/bin/sh
# tlw_guard.sh - start/stop FPS guard as a detached process
# Usage:
#   sh tlw_guard.sh start [fps]   start guard (fps optional, uses saved)
#   sh tlw_guard.sh stop          stop guard
#   sh tlw_guard.sh status        show status

DIR=$(dirname "$0")
[ -f "$DIR/tlw_common.sh" ] && . "$DIR/tlw_common.sh"
[ -f /data/local/tmp/tlw_common.sh ] && . /data/local/tmp/tlw_common.sh

LOG=/data/local/tmp/tlw_fps_daemon.log
PIDF=/data/local/tmp/tlw_guard.pid
SCRIPT=/data/local/tmp/tlw_fps.sh

ACTION="${1:-status}"
FPS="$2"

find_guard() {
  for p in /proc/[0-9]*; do
    if [ -r "$p/cmdline" ]; then
      c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
      case "$c" in
        *tlw_fps.sh\ daemon*) echo "${p#/proc/}" ;;
      esac
    fi
  done
}

case "$ACTION" in
  start)
    OLD=$(find_guard)
    if [ -n "$OLD" ]; then
      for p in $OLD; do kill -9 "$p" 2>/dev/null; done
      sleep 1
    fi

    if [ -n "$FPS" ]; then
      ARGS="daemon $FPS"
    else
      ARGS="daemon"
    fi

    # detach with setsid if available, else nohup
    if command -v setsid >/dev/null 2>&1; then
      setsid sh "$SCRIPT" $ARGS > "$LOG" 2>&1 < /dev/null &
    else
      nohup sh "$SCRIPT" $ARGS > "$LOG" 2>&1 < /dev/null &
    fi

    sleep 2
    NEW=$(find_guard)
    if [ -n "$NEW" ]; then
      echo "$NEW" > "$PIDF"
      echo "[+] guard running pid=$NEW"
      echo "[*] log:"
      head -4 "$LOG" 2>/dev/null | sed 's/^/    /'
    else
      echo "[x] guard failed to start"
      cat "$LOG" 2>/dev/null | head -10 | sed 's/^/    /'
      exit 1
    fi
    ;;

  stop)
    OLD=$(find_guard)
    if [ -z "$OLD" ]; then
      echo "[=] guard not running"
      exit 0
    fi
    for p in $OLD; do kill -9 "$p" 2>/dev/null; done
    rm -f "$PIDF"
    echo "[+] guard stopped"
    ;;

  status)
    OLD=$(find_guard)
    if [ -n "$OLD" ]; then
      echo "guard: running pid=$OLD"
      echo "log tail:"
      tail -5 "$LOG" 2>/dev/null | sed 's/^/    /'
    else
      echo "guard: stopped"
    fi
    ;;

  *)
    echo "usage: $0 {start [fps]|stop|status}"
    exit 1
    ;;
esac
