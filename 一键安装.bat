@echo off
chcp 936 >nul
title 东方归言录 汉化 v1.3 一键安装（模拟器/已root设备）
setlocal
set "ADB=%~dp0adb\adb.exe"
if not exist "%ADB%" set "ADB=adb"
set "PKG=jp.goodsmile.touhoulostwordglobal_android"
set "DEV=%~1"
if "%DEV%"=="" set "DEV=emulator-5554"
echo ============================================
echo   东方归言录 汉化 v1.3  一键安装
echo ============================================
echo 设备: %DEV%
echo.
"%ADB%" -s %DEV% get-state >nul 2>&1
if errorlevel 1 (
  echo [错误] 连接不到设备 %DEV%
  echo   1. 先启动模拟器
  echo   2. 确认 adb devices 能看到设备
  echo   3. 设备号不同就: 一键安装.bat 设备号
  pause
  exit /b 1
)
echo [1/5] 解压数据包（424 MB，约需 1 分钟）...
if exist "%TEMP%\lw_v13" rmdir /s /q "%TEMP%\lw_v13"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -LiteralPath '%~dp0lwlocal.zip' -DestinationPath '%TEMP%\lw_v13'"
if not exist "%TEMP%\lw_v13\lwlocal\master" (
  echo [错误] 解压失败，检查 lwlocal.zip 是否完整
  pause
  exit /b 1
)
echo [2/5] 推送到设备（约 1~2 分钟）...
"%ADB%" -s %DEV% shell "rm -rf /sdcard/tmp_lw; mkdir -p /sdcard/tmp_lw"
"%ADB%" -s %DEV% push "%TEMP%\lw_v13\lwlocal\bundles" "/sdcard/tmp_lw/"
"%ADB%" -s %DEV% push "%TEMP%\lw_v13\lwlocal\master" "/sdcard/tmp_lw/"
"%ADB%" -s %DEV% push "%~dp0apply.sh" "/sdcard/tmp_lw/apply.sh"
echo [3/5] 写入游戏目录（需要 root）...
"%ADB%" -s %DEV% shell "su -c 'sh /sdcard/tmp_lw/apply.sh'"
echo [4/5] 记录安装清单...
"%ADB%" -s %DEV% shell "su -c 'cd /sdcard/tmp_lw/bundles && for d in *; do echo $d; done > /sdcard/tmp_lw/installed.txt; ls /sdcard/tmp_lw/master >> /sdcard/tmp_lw/installed.txt; cp /sdcard/tmp_lw/installed.txt /sdcard/Android/data/%PKG%/files/lw_installed.txt'"
echo [5/5] 重启游戏...
"%ADB%" -s %DEV% shell am force-stop %PKG%
"%ADB%" -s %DEV% shell "monkey -p %PKG% -c android.intent.category.LAUNCHER 1"
echo.
echo 完成。进游戏看剧情/技能是否中文；如果是英文，进设置切换一次语言再切回来。
pause
