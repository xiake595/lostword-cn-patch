# build-jp-coexist.ps1 -- 日服共存版（和日服官方/日服改版同时装）
#
# 为什么不直接在命令行敲 build.ps1 -Pkg ...：
#   -Label / -OldLabel 里有日文，PowerShell 5.1 从命令行收非 ASCII 参数时按系统
#   代码页解码，很容易变乱码。写进脚本文件（UTF-8 with BOM）就没有这个问题。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

& "$root\build.ps1" `
  -BaseApk    "apk\jp\base.apk" `
  -SplitApk   "apk\jp\split_arm64.apk" `
  -OldPkg     "jp.goodsmile.touhoulostword_android" `
  -OldLabel   "東方ロストワード" `
  -Pkg        "jp.goodsmile.touhoulostword_andr0id" `
  -Label      "東方ロストＦＰＳ" `
  -Icon       "assets\tlw_icon_jp.png" `
  -Authority  "tlw.fps.boot.jpcoexist" `
  -Out        "out\TLW-jp-1.71.1-fps-coexist.apk"
