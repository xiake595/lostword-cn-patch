#!/system/bin/sh
# tlw_info.sh - one-line device info for the PC side to parse
# Output format:  SERVER|VERSION|RUNSTATE|FPS
#   SERVER   : Global / JP / CN / none
#   RUNSTATE : running / stopped
#   FPS      : current targetFrameRate (-1 = follow display)

DIR=$(dirname "$0")
[ -f "$DIR/tlw_common.sh" ] && . "$DIR/tlw_common.sh"
[ -f /data/local/tmp/tlw_common.sh ] && . /data/local/tmp/tlw_common.sh

PKG=$(detect_pkg)
if [ -z "$PKG" ]; then
  echo "none|-|stopped|-"
  exit 0
fi

SRV=$(detect_server "$PKG")
VER=$(get_version "$PKG")
PID=$(pidof "$PKG" 2>/dev/null)

if [ -z "$PID" ]; then
  echo "$SRV|$VER|stopped|-"
  exit 0
fi

# game running - try to read current fps
BASE=$(get_libunity_base "$PKG")
if [ -z "$BASE" ]; then
  echo "$SRV|$VER|starting|-"
  exit 0
fi

OFF=$(fps_offset_for "$PKG" "$VER")
if [ -z "$OFF" ]; then
  echo "$SRV|$VER|running|unknown"
  exit 0
fi

OFF_HEX=$(echo "$OFF" | sed 's/^0x//')
ADDR=$(hex_add "$BASE" "$OFF_HEX")

RAW=$(read_proc_mem "$PID" "$ADDR")
if [ -z "$RAW" ]; then
  echo "$SRV|$VER|running|readfail"
  exit 0
fi

VAL=$(hex_to_int "$RAW")

echo "$SRV|$VER|running|$VAL"
