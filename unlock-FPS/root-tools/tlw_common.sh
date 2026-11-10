#!/system/bin/sh
# ============================================================
# tlw_common.sh - shared library
# auto-detect: package name, version, libunity base, fps offset, root mode
#
# Supported servers:
#   Global : jp.goodsmile.touhoulostwordglobal_android
#   JP     : jp.goodsmile.touhoulostword_android
#   CN     : com.gg.touhoulw
# ============================================================

PKG_GLOBAL="jp.goodsmile.touhoulostwordglobal_android"
PKG_JP="jp.goodsmile.touhoulostword_android"
PKG_CN="com.gg.touhoulw"

# ---------- find game package ----------
# Priority:
#   1. a server that is actually RUNNING (a device can have Global and JP
#      installed side by side; picking the installed-but-idle one is wrong)
#   2. otherwise the usual install order Global > JP > CN
detect_pkg() {
  # 1. running process wins
  for p in "$PKG_GLOBAL" "$PKG_JP" "$PKG_CN"; do
    if pidof "$p" >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
  done

  # 2. fall back to installed
  for p in "$PKG_GLOBAL" "$PKG_JP" "$PKG_CN"; do
    if pm path "$p" >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

# ---------- which server ----------
detect_server() {
  case "$1" in
    "$PKG_GLOBAL") echo "Global" ;;
    "$PKG_JP")     echo "JP" ;;
    "$PKG_CN")     echo "CN" ;;
    *)             echo "Unknown" ;;
  esac
}

# ---------- version ----------
get_version() {
  dumpsys package "$1" 2>/dev/null | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r'
}

# ---------- libunity base ----------
get_libunity_base() {
  PID=$(pidof "$1" 2>/dev/null)
  [ -z "$PID" ] && return 1

  # direct read works when we are already root
  B=$(grep -m1 'libunity\.so' /proc/$PID/maps 2>/dev/null | cut -d'-' -f1)
  [ -n "$B" ] && { echo "$B"; return 0; }

  # otherwise try su (LDPlayer 9 / Android 9 needs this)
  if command -v su >/dev/null 2>&1; then
    B=$(su -c "grep -m1 'libunity\.so' /proc/$PID/maps 2>/dev/null | cut -d'-' -f1" 2>/dev/null)
    [ -n "$B" ] && { echo "$B"; return 0; }
  fi

  return 1
}

# ---------- read 4 bytes from process memory ----------
# tries direct read, falls back to su
# validate: 8 hex chars exactly (4 bytes little-endian)
is_hex8() {
  case "$1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
    *) return 1 ;;
  esac
}

read_proc_mem() {
  _pid="$1"
  _addr="$2"
  detect_dd

  # attempt 1: direct with the working dd variant
  _out=$($DD_CMD if=/proc/$_pid/mem bs=1 skip=$_addr count=4 2>/dev/null | od -An -tx1 | head -1 | tr -d ' \n')
  if is_hex8 "$_out"; then echo "$_out"; return 0; fi

  # attempt 2: via su with the working dd variant
  if command -v su >/dev/null 2>&1; then
    _out=$(su -c "$DD_CMD if=/proc/$_pid/mem bs=1 skip=$_addr count=4 2>/dev/null | od -An -tx1 | head -1 | tr -d ' \n'" 2>/dev/null)
    if is_hex8 "$_out"; then echo "$_out"; return 0; fi
  fi

  return 1
}

# ---------- write 4 bytes to process memory ----------
write_proc_mem() {
  _pid="$1"
  _addr="$2"
  _file="$3"

  detect_dd
  _want=$(od -An -tx1 $_file | head -1 | tr -d ' \n')
  [ -z "$_want" ] && return 1

  if [ "$DD_NOTRUNC" = "1" ]; then
    _conv="conv=notrunc"
  else
    _conv=""
  fi

  # attempt 1: direct with the working dd
  $DD_CMD if=$_file of=/proc/$_pid/mem bs=1 seek=$_addr count=4 $_conv >/dev/null 2>&1
  _chk=$(read_proc_mem "$_pid" "$_addr")
  if is_hex8 "$_chk" && [ "$_chk" = "$_want" ]; then return 0; fi

  # attempt 2: via su with the working dd
  if command -v su >/dev/null 2>&1; then
    su -c "$DD_CMD if=$_file of=/proc/$_pid/mem bs=1 seek=$_addr count=4 $_conv 2>/dev/null" >/dev/null 2>&1
    _chk=$(read_proc_mem "$_pid" "$_addr")
    if is_hex8 "$_chk" && [ "$_chk" = "$_want" ]; then return 0; fi
  fi

  # attempt 3: pipe into dd (works when conv= is unsupported)
  if command -v su >/dev/null 2>&1; then
    su -c "cat $_file | $DD_CMD of=/proc/$_pid/mem bs=1 seek=$_addr count=4 2>/dev/null" >/dev/null 2>&1
    _chk=$(read_proc_mem "$_pid" "$_addr")
    if is_hex8 "$_chk" && [ "$_chk" = "$_want" ]; then return 0; fi
  fi

  return 1
}

# ---------- known fps offset table ----------
# keyed by "pkg:version"
fps_offset_for() {
  KEY="$1:$2"
  case "$KEY" in
    # Global
    jp.goodsmile.touhoulostwordglobal_android:1.57.0) echo "0x199cc54" ;;
    # JP
    jp.goodsmile.touhoulostword_android:1.71.1)       echo "0x199cc54" ;;
    *) echo "" ;;
  esac
}

# legacy name kept for compatibility
fps_offset_for_version() {
  fps_offset_for "$PKG_CURRENT" "$1"
}

# ---------- root mode ----------
# 0 = already root (adb root), 1 = su available, 2 = none
detect_root_mode() {
  if [ "$(id -u)" = "0" ]; then
    ROOT_MODE="direct"
    return 0
  fi
  if command -v su >/dev/null 2>&1; then
    if su -c "id" 2>/dev/null | grep -q 'uid=0'; then
      ROOT_MODE="su"
      return 1
    fi
  fi
  ROOT_MODE="none"
  return 2
}

run_root() {
  CMD="$1"
  case "$ROOT_MODE" in
    direct) sh -c "$CMD" ;;
    su)     su -c "$CMD" ;;
    *)      return 127 ;;
  esac
}

check_root() {
  detect_root_mode
  [ "$ROOT_MODE" != "none" ]
}


# ---------- dd compatibility ----------
# Some emulators (LDPlayer) ship a broken /system/bin/dd symlink -> toolbox
# but toybox dd works. Detect once and cache the result.
DD_CMD=""
DD_NOTRUNC=0

detect_dd() {
  [ -n "$DD_CMD" ] && return 0

  # toybox dd first: system dd on Android 9 lacks conv=notrunc
  if toybox dd if=/dev/zero of=/dev/null bs=1 count=1 >/dev/null 2>&1; then
    DD_CMD="toybox dd"
    DD_NOTRUNC=1
    return 0
  fi

  if dd if=/dev/zero of=/dev/null bs=1 count=1 >/dev/null 2>&1; then
    DD_CMD="dd"
    # test if conv=notrunc works
    if dd if=/dev/zero of=/dev/null bs=1 count=1 conv=notrunc >/dev/null 2>&1; then
      DD_NOTRUNC=1
    else
      DD_NOTRUNC=0
    fi
    return 0
  fi

  if command -v busybox >/dev/null 2>&1; then
    if busybox dd if=/dev/zero of=/dev/null bs=1 count=1 >/dev/null 2>&1; then
      DD_CMD="busybox dd"
      DD_NOTRUNC=1
      return 0
    fi
  fi

  DD_CMD="dd"
  DD_NOTRUNC=0
  return 1
}

# run dd with the working variant, suppress its stderr stats
run_dd() {
  detect_dd
  $DD_CMD "$@" 2>/dev/null
}

# ---------- hex addition ----------
# Different emulators need different strategies:
#   - LDPlayer 14 / MuMu: awk works, keeps full 53-bit precision
#   - LDPlayer 9 (Android 9): awk substr() is broken, printf %d works
#   - mksh $(( )) is 32-bit only, never use for 48-bit addresses
# Order: awk -> printf -> nibble loop
hex_add() {
  _b="$1"
  _o="$2"
  case "$_b" in 0x*) _b=$(echo "$_b" | cut -c3-);; esac
  case "$_o" in 0x*) _o=$(echo "$_o" | cut -c3-);; esac

  # strategy 1: awk (highest precision)
  _r=$(awk -v b="$_b" -v o="$_o" 'BEGIN{
    n = length(b); bv = 0
    for(i=1;i<=n;i++){
      c = tolower(substr(b,i,1))
      d = index("0123456789abcdef", c) - 1
      if(d < 0) d = 0
      bv = bv * 16 + d
    }
    m = length(o); ov = 0
    for(i=1;i<=m;i++){
      c = tolower(substr(o,i,1))
      d = index("0123456789abcdef", c) - 1
      if(d < 0) d = 0
      ov = ov * 16 + d
    }
    printf "%.0f", bv + ov
  }' 2>/dev/null)

  case "$_r" in
    ''|*[!0-9]*) _r="" ;;
    *) [ "$_r" = "0" ] && _r="" ;;
  esac
  [ -n "$_r" ] && { echo "$_r"; return 0; }

  # strategy 2: printf %d (LDPlayer 9 fallback)
  _bv=$(printf '%d' "0x$_b" 2>/dev/null)
  _ov=$(printf '%d' "0x$_o" 2>/dev/null)
  case "$_bv" in ''|*[!0-9]*) _bv="" ;; esac
  case "$_ov" in ''|*[!0-9]*) _ov="" ;; esac
  if [ -n "$_bv" ] && [ -n "$_ov" ]; then
    _r=$(awk -v x="$_bv" -v y="$_ov" 'BEGIN{ printf "%.0f", x + y }' 2>/dev/null)
    case "$_r" in
      ''|*[!0-9]*) ;;
      *) echo "$_r"; return 0 ;;
    esac
  fi

  # strategy 3: nibble loop
  _v=0; _i=1
  while [ $_i -le ${#_b} ]; do
    _c=$(echo "$_b" | cut -c$_i)
    case "$_c" in
      0) _d=0;; 1) _d=1;; 2) _d=2;; 3) _d=3;; 4) _d=4;;
      5) _d=5;; 6) _d=6;; 7) _d=7;; 8) _d=8;; 9) _d=9;;
      a|A) _d=10;; b|B) _d=11;; c|C) _d=12;; d|D) _d=13;;
      e|E) _d=14;; f|F) _d=15;; *) _d=0;;
    esac
    _v=$((_v * 16 + _d)); _i=$((_i + 1))
  done
  _w=0; _i=1
  while [ $_i -le ${#_o} ]; do
    _c=$(echo "$_o" | cut -c$_i)
    case "$_c" in
      0) _d=0;; 1) _d=1;; 2) _d=2;; 3) _d=3;; 4) _d=4;;
      5) _d=5;; 6) _d=6;; 7) _d=7;; 8) _d=8;; 9) _d=9;;
      a|A) _d=10;; b|B) _d=11;; c|C) _d=12;; d|D) _d=13;;
      e|E) _d=14;; f|F) _d=15;; *) _d=0;;
    esac
    _w=$((_w * 16 + _d)); _i=$((_i + 1))
  done
  echo $((_v + _w))
}

# ---------- little-endian hex -> signed int ----------
# pure shell (LDPlayer 9 awk substr is broken)
hex_to_int() {
  _h="$1"
  _n=$((${#_h} / 2))
  _v=0
  _i=$_n
  while [ $_i -ge 1 ]; do
    _pos=$(((_i - 1) * 2 + 1))
    _pair=$(echo "$_h" | cut -c$_pos-$((_pos + 1)))
    _hi=$(echo "$_pair" | cut -c1)
    _lo=$(echo "$_pair" | cut -c2)
    case "$_hi" in
      0) _dh=0;; 1) _dh=1;; 2) _dh=2;; 3) _dh=3;; 4) _dh=4;;
      5) _dh=5;; 6) _dh=6;; 7) _dh=7;; 8) _dh=8;; 9) _dh=9;;
      a|A) _dh=10;; b|B) _dh=11;; c|C) _dh=12;; d|D) _dh=13;;
      e|E) _dh=14;; f|F) _dh=15;; *) _dh=0;;
    esac
    case "$_lo" in
      0) _dl=0;; 1) _dl=1;; 2) _dl=2;; 3) _dl=3;; 4) _dl=4;;
      5) _dl=5;; 6) _dl=6;; 7) _dl=7;; 8) _dl=8;; 9) _dl=9;;
      a|A) _dl=10;; b|B) _dl=11;; c|C) _dl=12;; d|D) _dl=13;;
      e|E) _dl=14;; f|F) _dl=15;; *) _dl=0;;
    esac
    _v=$((_v * 256 + _dh * 16 + _dl))
    _i=$((_i - 1))
  done
  if [ $_v -ge 2147483648 ]; then
    _v=$((_v - 4294967296))
  fi
  echo $_v
}

# ---------- output ----------
info()  { echo "[*] $*"; }
ok()    { echo "[+] $*"; }
warn()  { echo "[!] $*"; }
err()   { echo "[x] $*"; }
