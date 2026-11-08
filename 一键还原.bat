@echo off
chcp 936 >nul
title 东方归言录 汉化插件
setlocal
set "ADB=%~dp0adb\adb.exe"
set "PKG=jp.goodsmile.touhoulostwordglobal_android"
set "DEV=%~1"
if "%DEV%"=="" set "DEV=emulator-5554"
echo 这会删除本插件覆盖的文件（不影响游戏其他缓存）。
pause
"%ADB%" -s %DEV% shell "su -c 'F=/sdcard/Android/data/%PKG%/files/lw_installed.txt; if [ -f $F ]; then while read n; do rm -rf /sdcard/Android/data/%PKG%/files/UnityCache/Shared/$n; rm -f /data/data/%PKG%/files/cache/$n; done < $F; rm -f $F; fi'"
echo.
echo 已删除汉化文件。重新启动游戏，缺失的部分会自动重新下载。
pause