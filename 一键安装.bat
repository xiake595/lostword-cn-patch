@echo off
chcp 936 >nul
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

rem 版本校验
for /f "tokens=2 delims==" %%v in ('"%ADB%" -s %DEV% shell dumpsys package %PKG% ^| findstr /C:"versionName"') do set "GV=%%v"
set "GV=%GV: =%"
if not "%GV%"=="1.57.0" (
  echo [警告] 游戏版本是 %GV%，本补丁对应 1.57.0
  echo 版本不一致可能资源错乱，建议先更新补丁
  pause
)

echo [1/4] 推送文件（约 380 MB，需要 1~2 分钟，请勿关闭窗口）...
"%ADB%" -s %DEV% shell "rm -rf /sdcard/tmp_lw"
"%ADB%" -s %DEV% shell "mkdir -p /sdcard/tmp_lw"
"%ADB%" -s %DEV% push "%~dp0数据\bundles" "/sdcard/tmp_lw/"
"%ADB%" -s %DEV% push "%~dp0数据\master" "/sdcard/tmp_lw/"
"%ADB%" -s %DEV% push "%~dp0数据\apply.sh" "/sdcard/tmp_lw/apply.sh"

echo [2/4] 写入游戏目录（需要 root）...
"%ADB%" -s %DEV% shell "su -c 'sh /sdcard/tmp_lw/apply.sh'"

echo [3/4] 记录安装清单 ...
"%ADB%" -s %DEV% shell "su -c 'cd /sdcard/tmp_lw/bundles && for d in *; do echo $d; done > /sdcard/tmp_lw/installed.txt; ls /sdcard/tmp_lw/master >> /sdcard/tmp_lw/installed.txt; cp /sdcard/tmp_lw/installed.txt /sdcard/Android/data/%PKG%/files/lw_installed.txt'"

echo [4/4] 启动游戏 ...
"%ADB%" -s %DEV% shell am force-stop %PKG%
"%ADB%" -s %DEV% shell "monkey -p %PKG% -c android.intent.category.LAUNCHER 1"

echo.
echo 完成。进游戏看效果；如仍英文，游戏内清除缓存后重进。
pause