@echo off
chcp 936 >nul
title 东方归言录 汉化 v1.3 一键还原
setlocal
set "ADB=%~dp0adb\adb.exe"
if not exist "%ADB%" set "ADB=adb"
set "PKG=jp.goodsmile.touhoulostwordglobal_android"
set "DEV=%~1"
if "%DEV%"=="" set "DEV=emulator-5554"
echo 这会删除汉化写入的文件（不影响游戏存档）。
pause
"%ADB%" -s %DEV% shell "su -c 'F=/sdcard/Android/data/%PKG%/files/lw_installed.txt; if [ -f $F ]; then while read n; do rm -rf /sdcard/Android/data/%PKG%/files/UnityCache/Shared/$n; rm -f /data/data/%PKG%/files/cache/$n; done < $F; rm -f $F; fi'"
echo.
echo 已删除汉化文件，游戏启动时会自动重新下载缺失部分。
pause
