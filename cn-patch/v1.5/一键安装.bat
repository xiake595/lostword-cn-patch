@echo off
chcp 65001 >nul
title 东方归言录 中文补丁 v1.5

set PY=C:\Users\1\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe
if not exist "%PY%" (
    where python >nul 2>nul
    if errorlevel 1 (
        echo [错误] 找不到 Python。
        echo 请安装 Python 3.9+ 后重试，或直接用命令行跑 tlw_install.py。
        pause
        exit /b 1
    )
    set PY=python
)

echo ============================================
echo   东方归言录 国际服 简体中文补丁 v1.5
echo ============================================
echo.
echo   1  安装补丁
echo   2  检查是否装好
echo   3  还原成英文
echo   0  退出
echo.
set /p CH=请输入数字:

if "%CH%"=="1" goto INSTALL
if "%CH%"=="2" goto VERIFY
if "%CH%"=="3" goto RESTORE
goto END

:INSTALL
echo.
echo 请确认：游戏已安装、已启动过一次、模拟器已开启。
echo 默认设备 emulator-5556（LDPlayer 实例 1）。
echo.
set /p SER=设备号（直接回车用默认）:
if "%SER%"=="" (
    "%PY%" -I tlw_install.py install
) else (
    "%PY%" -I tlw_install.py install --serial %SER%
)
goto DONE

:VERIFY
"%PY%" -I tlw_install.py verify
goto DONE

:RESTORE
echo.
echo 这会撤销所有中文改动，恢复英文。
set /p OK=确认还原？(y/N):
if /i not "%OK%"=="y" goto END
"%PY%" -I tlw_install.py restore
goto DONE

:DONE
echo.
echo 完成。建议重启游戏后检查效果。
pause
:END
