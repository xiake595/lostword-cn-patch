@echo off
chcp 65001 >nul
title 东方归言录 汉化插件
setlocal
set "ADB=%~dp0adb\adb.exe"
set "PKG=jp.goodsmile.touhoulostwordglobal_android"
set "DEV=%~1"
if "%DEV%"=="" set "DEV=emulator-5554"

echo ============================================
echo    东方归言录 汉化插件  一键安装
echo ============================================
echo 设备: %DEV%
echo.
"%ADB%" -s %DEV% get-state >nul 2>&1
if errorlevel 1 (
  echo [错误] 连接不到设备 %DEV%
  echo 1. 先启动模拟器
  echo 2. 确认 adb devices 里有设备
  echo 3. 设备号不同：一键安装.bat 你的设备号
  pause
  exit /b 1
)
"%ADB%" -s %DEV% shell "su -c id" | findstr /C:"uid=0" >nul
if errorlevel 1 (
  echo [错误] 模拟器没有 root
  echo 雷电：设置 - 其他设置 - ROOT权限 打开后重启
  pause
  exit /b 1
)
echo [1/4] 推送文件到设备 ...
"%ADB%" -s %DEV% shell "rm -rf /sdcard/tmp_lw"
"%ADB%" -s %DEV% shell "mkdir -p /sdcard/tmp_lw"
"%ADB%" -s %DEV% push "%~dp0数据\bundles" "/sdcard/tmp_lw/" >nul
"%ADB%" -s %DEV% push "%~dp0数据\master" "/sdcard/tmp_lw/" >nul
"%ADB%" -s %DEV% push "%~dp0数据\apply.sh" "/sdcard/tmp_lw/apply.sh" >nul
echo [2/4] 写入游戏目录（需要 root）...
"%ADB%" -s %DEV% shell "su -c 'sh /sdcard/tmp_lw/apply.sh'"
echo [3/4] 清理临时文件 ...
"%ADB%" -s %DEV% shell "rm -rf /sdcard/tmp_lw"
echo [4/4] 重启游戏 ...
"%ADB%" -s %DEV% shell am force-stop %PKG%
timeout /t 1 >nul
"%ADB%" -s %DEV% shell am start -n %PKG%/com.google.firebase.MessagingUnityPlayerActivity
echo.
echo 完成。进游戏看效果；如仍英文，游戏内清除缓存后重进。
pause