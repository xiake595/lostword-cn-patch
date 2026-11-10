@echo off
setlocal enabledelayedexpansion
chcp 936 >nul
title Touhou LostWord Tool v2.4

set DIR=%~dp0
REM strip trailing backslash - %~dp0 always ends with one
if "%DIR:~-1%"=="\" set DIR=%DIR:~0,-1%
set PKG_INTL=jp.goodsmile.touhoulostwordglobal_android
set PKG_CN=com.gg.touhoulw
set PKG_JP=jp.goodsmile.touhoulostword_android

echo ==========================================
echo   Touhou LostWord Tool  v2.4
echo ==========================================
echo.
echo   正在检测模拟器，请耐心等待...
echo   Detecting emulators, please wait...
echo.
echo   (扫描模拟器端口，通常几秒钟)
echo.

REM ===== find adb =====
set ADB=
if exist "%DIR%\adb\adb.exe" set ADB=%DIR%\adb\adb.exe
if not defined ADB call :try_where
if not defined ADB if exist "D:\adb\adb.exe" set ADB=D:\adb\adb.exe
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if not defined ADB if exist "C:\adb\adb.exe" set ADB=C:\adb\adb.exe
if not defined ADB if exist "C:\platform-tools\adb.exe" set ADB=C:\platform-tools\adb.exe
if not defined ADB goto no_adb
echo [*] adb: %ADB%

REM ===== find devices (all, then dedupe by boot_id) =====
echo [*] scanning emulators...
REM Only connect to ports that are actually LISTENING. Connecting to a dead
REM port makes adb wait for a timeout (~2s each), which made startup crawl.
netstat -an > "%TEMP%\tlw_ports.txt" 2>nul
for %%P in (7555 5555 16384 5556 16480 16512 16448 16416 5557 5558) do (
  findstr /c:":%%P " "%TEMP%\tlw_ports.txt" | findstr /c:"LISTENING" >nul 2>&1
  if not errorlevel 1 (
    "%ADB%" connect 127.0.0.1:%%P >nul 2>&1 <nul
  )
)
del /q "%TEMP%\tlw_ports.txt" >nul 2>&1
set DEVLIST=
for /f "tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
  if "%%b"=="device" (
    if not "%%a"=="List" set DEVLIST=!DEVLIST! %%a
  )
)
if not defined DEVLIST goto no_dev

REM dedupe by boot_id (write to file first - for /f + adb eats stdin)
set UNIQLIST=
set DCOUNT=0
set "BIDDIR=%TEMP%\tlw_bid"
if exist "%BIDDIR%" rd /s /q "%BIDDIR%" >nul 2>&1
mkdir "%BIDDIR%" >nul 2>&1
set "BIDX=0"
for %%d in (!DEVLIST!) do (
  set /a BIDX+=1
  "%ADB%" -s %%d shell cat /proc/sys/kernel/random/boot_id >"%BIDDIR%\!BIDX!.txt" 2>nul <nul
)
set "BIDX=0"
for %%d in (!DEVLIST!) do (
  set /a BIDX+=1
  set "B1="
  for /f "usebackq delims=" %%x in ("%BIDDIR%\!BIDX!.txt") do if not defined B1 set "B1=%%x"
  set "SEEN="
  if defined B1 if exist "%BIDDIR%\seen_!B1!" set "SEEN=1"
  if not defined SEEN (
    if defined B1 type nul >"%BIDDIR%\seen_!B1!"
    set UNIQLIST=!UNIQLIST! %%d
    set /a DCOUNT+=1
  )
)

echo.
if !DCOUNT! EQU 1 goto dev_single
if !DCOUNT! GTR 1 goto dev_multi
goto no_dev

:dev_single
for %%d in (!UNIQLIST!) do set "DEV=%%d"
echo [*] device: !DEV!
goto dev_done

:dev_multi
echo [*] 检测到 !DCOUNT! 台设备 / found !DCOUNT! devices:
set "IDX=0"
for %%d in (!UNIQLIST!) do (
  set /a IDX+=1
  set "SVR=?"
  "%ADB%" -s %%d shell "sh /data/local/tmp/tlw_info.sh" >"%TEMP%\tlw_svr.txt" 2>nul <nul
  set "SVR="
  for /f "usebackq delims=" %%i in ("%TEMP%\tlw_svr.txt") do set "SVR=%%i"
  if not defined SVR set "SVR=?"
  echo     !IDX!. %%d  !SVR!
)
echo.
set "PICK="
set /p PICK=选择设备编号 Select device number: 
if not defined PICK goto no_dev
set "IDX=0"
for %%d in (!UNIQLIST!) do (
  set /a IDX+=1
  if "!IDX!"=="!PICK!" set "DEV=%%d"
)
if not defined DEV (
  echo [x] 无效选择 invalid choice
  goto no_dev
)
echo [*] 已选择 selected: !DEV!
goto dev_done

:dev_done

REM ===== find game (Global / JP / CN) =====
set PKG=
set SERVER=
"%ADB%" -s %DEV% shell pm path %PKG_INTL% >"%TEMP%\tlw_p.txt" 2>nul <nul
findstr /c:"package:" "%TEMP%\tlw_p.txt" >nul 2>&1
if not errorlevel 1 (
  set PKG=%PKG_INTL%
  set SERVER=Global
)
if not defined PKG (
  "%ADB%" -s %DEV% shell pm path %PKG_JP% >"%TEMP%\tlw_p.txt" 2>nul <nul
  findstr /c:"package:" "%TEMP%\tlw_p.txt" >nul 2>&1
  if not errorlevel 1 (
    set PKG=%PKG_JP%
    set SERVER=JP
  )
)
if not defined PKG (
  "%ADB%" -s %DEV% shell pm path %PKG_CN% >"%TEMP%\tlw_p.txt" 2>nul <nul
  findstr /c:"package:" "%TEMP%\tlw_p.txt" >nul 2>&1
  if not errorlevel 1 (
    set PKG=%PKG_CN%
    set SERVER=CN
  )
)
if not defined PKG goto no_game
echo [*] game: %PKG%  (%SERVER%)
REM ===== root (two modes: su / adb root) =====
set ROOTMODE=none
"%ADB%" -s %DEV% shell id >"%TEMP%\tlw_r.txt" 2>nul <nul
findstr /c:"uid=0" "%TEMP%\tlw_r.txt" >nul 2>&1
if not errorlevel 1 goto root_direct

"%ADB%" -s %DEV% shell "su -c id" >"%TEMP%\tlw_r2.txt" 2>nul <nul
findstr /c:"uid=0" "%TEMP%\tlw_r2.txt" >nul 2>&1
if not errorlevel 1 goto root_su

echo [*] su not found, trying adb root (may restart adbd)...
call :adb_root
"%ADB%" -s %DEV% shell id >"%TEMP%\tlw_r3.txt" 2>nul <nul
findstr /c:"uid=0" "%TEMP%\tlw_r3.txt" >nul 2>&1
if not errorlevel 1 set ROOTMODE=direct
goto root_done

:root_direct
set ROOTMODE=direct
goto root_done

:root_su
set ROOTMODE=su
goto root_done

:adb_root
"%ADB%" -s %DEV% root >nul 2>&1 <nul
ping -n 3 127.0.0.1 >nul 2>&1
"%ADB%" -s %DEV% wait-for-device >nul 2>&1 <nul
goto :eof

:root_done
if "%ROOTMODE%"=="none" (
  echo [!] root NOT available
  echo     MuMu 12: Settings -^> Other -^> enable root
  echo     MuMu 15: tried adb root already
  echo     LDPlayer: Settings -^> Other -^> enable root
  echo.
) else (
  echo [*] root: ok ^(%ROOTMODE%^)
)

REM ===== push =====
echo [*] pushing scripts...
for %%F in (tlw_common.sh tlw_reroll.sh tlw_guard_loop.sh tlw_fps.sh tlw_guard.sh tlw_info.sh) do (
  "%ADB%" -s %DEV% push "%DIR%\%%F" "/data/local/tmp/%%F" >nul 2>&1 <nul
)
"%ADB%" -s %DEV% shell chmod 755 /data/local/tmp/tlw_*.sh >nul 2>&1 <nul

:menu
echo.
echo ==========================================
echo   1. 环境自检 Environment check  (先跑这个 run first)
echo   2. 制作备份 Prep backup        (只需一次 once, ~870MB)
echo   3. 开始刷号 Start reroll       (清号并启动 wipe + launch)
echo   4. 查看状态 Show status
echo   5. 手动回填 Manual restore cache
echo   6. 停止守护 Stop guard
echo   7. 解锁帧率 Unlock FPS         (自动探测 auto detect)
echo   M. 多设备管理 Multi-Device    (自动识别服 auto-detect server)
echo   8. 重启守护 Restart Guard   (默认已自动开启 auto by default)
echo   9. 停止帧率守护 Stop FPS Guard
echo   R. 还原帧率 Restore FPS default
echo   D. 仅探测偏移 Detect offset    (诊断 diagnostic)
echo   0. 退出 Exit
echo.
echo   ------------------------------------------
echo    [B站] 求关注 @修龙泉
echo    [致谢] 御坂11451号-
echo   ------------------------------------------
echo ==========================================
set CH=
set /p CH=Select: 

REM empty input (EOF / Ctrl+C / stray enter) -> exit instead of looping forever
if not defined CH exit /b 0

if "%CH%"=="1" goto m_check
if "%CH%"=="2" goto m_prep
if "%CH%"=="3" goto m_reroll
if "%CH%"=="4" goto m_status
if "%CH%"=="5" goto m_restore
if "%CH%"=="6" goto m_stop
if "%CH%"=="7" goto m_fps
if /i "%CH%"=="M" goto m_multi
if "%CH%"=="8" goto m_fpsguard
if "%CH%"=="9" goto m_fpsstop
if /i "%CH%"=="R" goto m_fps0
if /i "%CH%"=="D" goto m_detect
if "%CH%"=="0" exit /b 0
goto menu

:m_check
echo.
call :rsh "sh /data/local/tmp/tlw_reroll.sh check"
goto menu

:m_prep
echo.
call :rsh "sh /data/local/tmp/tlw_reroll.sh prep"
goto menu

:m_status
echo.
call :rsh "sh /data/local/tmp/tlw_reroll.sh status"
goto menu

:m_restore
echo.
call :rsh "sh /data/local/tmp/tlw_reroll.sh restore"
goto menu

:m_stop
echo.
call :rsh "sh /data/local/tmp/tlw_reroll.sh stop"
goto menu

:m_multi
echo.
echo ==========================================
echo   多设备管理 Multi-Device
echo ==========================================
echo   1. 查看所有设备状态 Show status
echo   2. 全部设为 165fps  Set all to 165
echo   3. 全部自定义 Set all custom
echo   4. 停止所有守护 Stop all guards
echo   5. 解除解帧 Restore all to default  (停止守护 + 帧率还原)
echo   0. 返回 Back
echo ==========================================
set MCH=
set /p MCH=Select: 
if not defined MCH goto menu
if "%MCH%"=="0" goto menu
if "%MCH%"=="1" goto multi_status
if "%MCH%"=="2" goto multi_165
if "%MCH%"=="3" goto multi_custom
if "%MCH%"=="4" goto multi_stop
if "%MCH%"=="5" goto multi_restore
goto m_multi

:multi_status
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_multi.ps1" -Status -Dir "%DIR%"
goto m_multi

:multi_165
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_multi.ps1" -Fps 165 -Dir "%DIR%"
goto m_multi

:multi_custom
echo.
set MFPS=
set /p MFPS=输入帧率 Enter FPS: 
if not defined MFPS goto m_multi
echo %MFPS%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 ( echo [x] 请输入数字 & goto multi_custom )
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_multi.ps1" -Fps %MFPS% -Dir "%DIR%"
goto m_multi

:multi_restore
echo.
echo [*] 停止所有守护 + 还原帧率 Restoring all devices...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_multi.ps1" -Restore -Dir "%DIR%"
goto m_multi

:multi_stop
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_multi.ps1" -Stop -Dir "%DIR%"
goto m_multi

:m_fpsguard
echo.
echo ==========================================
echo   帧率守护 FPS Guard
echo ==========================================
echo   Game resets targetFrameRate to 0 when loading a stage.
echo   Guard re-applies your target every second.
echo.
echo   使用上次设置的帧率 Use last FPS setting?
set GCH=
set /p GCH=Continue? [Y/n]: 
if /i "%GCH%"=="n" goto m_fps
echo.
call :get_lib
if not exist "%DIR%\libunity_dump.so" goto fps_guard_nolib
set OFFSET=
for /f "delims=" %%o in ('powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_elf_scan.ps1" "%DIR%\libunity_dump.so" 2^>nul') do (
    echo %%o| findstr /r "^0x" >nul && set OFFSET=%%o
  )
if defined OFFSET call :rsh "echo %PKG% %OFFSET% > /data/local/tmp/tlw_fps_offset.txt"
:fps_guard_nolib
echo [*] 启动守护 starting guard...
call :rsh "sh /data/local/tmp/tlw_guard.sh start"
echo.
echo [*] Guard log:
call :rsh "tail -5 /data/local/tmp/tlw_fps_daemon.log 2>/dev/null"
echo.
echo [i] Guard runs on device. Use option 9 to stop it.
echo [i] 守护在模拟器里运行，按 9 停止
if exist "%DIR%\libunity_dump.so" del /q "%DIR%\libunity_dump.so" >nul 2>&1
goto menu

:m_fpsstop
echo.
call :rsh "sh /data/local/tmp/tlw_guard.sh stop"
goto menu

:m_fps0
echo.
call :rsh "sh /data/local/tmp/tlw_guard.sh stop"
call :rsh "sh /data/local/tmp/tlw_fps.sh 0"
echo [*] 守护已停止 guard stopped
REM clean up the 26MB temp dump
if exist "%DIR%\libunity_dump.so" del /q "%DIR%\libunity_dump.so" >nul 2>&1
goto menu

:m_reroll
echo.
call :rsh "sh /data/local/tmp/tlw_reroll.sh start"
echo.
echo ------------------------------------------
echo  Play the tutorial now.
echo  At the download prompt: click CANCEL
echo  Then click Game Start.
echo ------------------------------------------
goto menu

:m_fps
echo.
echo ==========================================
echo   FPS Setting / 帧率设置
echo ==========================================
echo   1. 165 fps  (165Hz full)
echo   2. 82 fps   (=165/2)
echo   3. 55 fps   (=165/3)
echo   4. 60 fps
echo   5. 90 fps
echo   6. 120 fps
echo   7. Custom / 自定义
echo   0. Back / 返回
echo ==========================================
set FPSCH=
set FPSVAL=
set /p FPSCH=Select: 
if not defined FPSCH goto menu
if "%FPSCH%"=="0" goto menu
if "%FPSCH%"=="1" set FPSVAL=165
if "%FPSCH%"=="2" set FPSVAL=82
if "%FPSCH%"=="3" set FPSVAL=55
if "%FPSCH%"=="4" set FPSVAL=60
if "%FPSCH%"=="5" set FPSVAL=90
if "%FPSCH%"=="6" set FPSVAL=120
if "%FPSCH%"=="7" goto fps_custom
if not defined FPSVAL goto m_fps
goto fps_apply

:fps_custom
echo.
echo Enter target FPS / 输入目标帧率 (1-1000)
set FPSVAL=
set /p FPSVAL=FPS: 
if not defined FPSVAL goto m_fps
echo %FPSVAL%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 goto fps_badnum
if %FPSVAL% LSS 1 goto fps_toosmall
if %FPSVAL% GTR 1000 goto fps_toolarge
goto fps_apply

:fps_badnum
echo [x] Please enter a number / 请输入数字
goto fps_custom

:fps_toosmall
echo [x] Too small / 太小
goto fps_custom

:fps_toolarge
echo [x] Too large / 太大
goto fps_custom

:fps_apply
echo.
echo [*] Target / 目标: %FPSVAL% fps
call :get_lib
if not exist "%DIR%\libunity_dump.so" goto no_detect
set OFFSET=
for /f "delims=" %%o in ('powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_elf_scan.ps1" "%DIR%\libunity_dump.so" 2^>nul') do (
    echo %%o| findstr /r "^0x" >nul && set OFFSET=%%o
  )
if not defined OFFSET goto no_detect
echo [+] offset: %OFFSET%
call :rsh "echo %PKG% %OFFSET% > /data/local/tmp/tlw_fps_offset.txt"
call :rsh "sh /data/local/tmp/tlw_fps.sh %FPSVAL%"
REM auto-start guard
echo [*] 自动启动帧率守护 auto-starting guard...
call :rsh "sh /data/local/tmp/tlw_guard.sh start %FPSVAL%"
ping -n 2 127.0.0.1 >nul 2>&1
echo [+] 守护已启动 guard running - 关卡加载后会自动补回
if exist "%DIR%\libunity_dump.so" del /q "%DIR%\libunity_dump.so" >nul 2>&1
goto menu

:m_detect
echo.
call :get_lib
if not exist "%DIR%\libunity_dump.so" goto menu
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIR%\tlw_elf_scan.ps1" "%DIR%\libunity_dump.so" -List
goto menu
:get_lib
if exist "%DIR%\libunity_dump.so" goto :eof
echo [*] extracting libunity.so...
call :rsh "rm -rf /data/local/tmp/tlw_d; mkdir -p /data/local/tmp/tlw_d"
call :rsh "for p in $(pm path %PKG% | sed s/package://); do unzip -o $p lib/*/libunity.so -d /data/local/tmp/tlw_d; done"
"%ADB%" -s %DEV% pull /data/local/tmp/tlw_d/lib/arm64-v8a/libunity.so "%DIR%\libunity_dump.so" >nul 2>&1 <nul
goto :eof

:rsh
REM run command as root, respecting ROOTMODE
REM usage: call :rsh "command"
set "RSHCMD=%~1"
if "%ROOTMODE%"=="direct" (
  "%ADB%" -s %DEV% shell "!RSHCMD!" <nul
) else (
  "%ADB%" -s %DEV% shell "su -c '!RSHCMD!'" <nul
)
goto :eof

:try_where
where adb >nul 2>&1
if not errorlevel 1 set ADB=adb
goto :eof

:no_adb
echo [x] adb not found.
echo     Put adb.exe into a subfolder named "adb" next to this bat,
echo     or install Android platform-tools and add it to PATH.
pause
exit /b 1

:no_dev
echo [x] no device. Start your emulator first.
pause
exit /b 1

:no_game
echo [x] Touhou LostWord not installed on this device.
pause
exit /b 1

:no_detect
echo [x] offset detection failed
echo     game may have updated - report the version number
pause
goto menu
