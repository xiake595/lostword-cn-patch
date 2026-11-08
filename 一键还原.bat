@echo off
chcp 65001 >nul
title 东方归言录 汉化插件
setlocal
set "ADB=%~dp0adb\adb.exe"
set "PKG=jp.goodsmile.touhoulostwordglobal_android"
set "DEV=%~1"
if "%DEV%"=="" set "DEV=emulator-5554"

echo 这会把汉化文件删掉，游戏会重新下载原版资源。
pause
"%ADB%" -s %DEV% shell "su -c 'rm -rf /sdcard/Android/data/%PKG%/files/UnityCache /data/data/%PKG%/files/cache'"
echo 完成。重新启动游戏即可下载原版资源。
pause