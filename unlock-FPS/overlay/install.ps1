# install.ps1 -- 把打好包的 APK 装进模拟器/真机
#
# 重打包换了签名，Android 不允许覆盖安装，所以必须 uninstall 再 install。
#
# 但是：`pm uninstall <pkg>` 会连 /data/data/<pkg> 一起删（Android 10+ 实测如此）。
# 所以要保存档只能先备份、装完再灌回去。本脚本默认这么做（需要 root）：
#
#   1. su tar 备份 /data/data/<pkg> 到 /sdcard
#   2. pm uninstall
#   3. pm install
#   4. su tar 解回、chown、restorecon
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Serial emulator-5558
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Wipe      # 不要存档

param(
    [string]$Serial = "",
    [string]$Apk    = "out\TLW-global-1.57.0-fps.apk",
    [string]$Pkg    = "jp.goodsmile.touhoulostwordglobal_android",
    [switch]$Wipe
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = "D:\adb\adb.exe" }
if (-not (Test-Path $adb)) { throw "找不到 adb，请把 adb 加进 PATH" }
if (-not (Test-Path $Apk)) { throw "找不到 $Apk，先跑 build.ps1" }

$ErrorActionPreference = "Continue"

function Adb([string[]]$a) {
    $out = & $adb -s $Serial @a 2>&1 | ForEach-Object { "$_" }
    return $out
}

# 选设备
if (-not $Serial) {
    $devs = @((& $adb devices 2>&1) | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] })
    if ($devs.Count -eq 0) { throw "没有已连接的设备" }
    if ($devs.Count -gt 1) {
        Write-Host "多台设备，用 -Serial 指定其中一台：" -ForegroundColor Yellow
        $devs | ForEach-Object { Write-Host "  $_" }
        throw "需要 -Serial"
    }
    $Serial = $devs[0]
}
Write-Host "device: $Serial" -ForegroundColor Cyan

$remote = "/data/local/tmp/tlw_fps.apk"
$tar    = "/sdcard/tlw_data_backup.tar"

Write-Host "[1/6] 停掉游戏" -ForegroundColor Cyan
Adb @("shell", "am force-stop $Pkg") | Out-Null

$hasRoot = ((Adb @("shell", "su -c id")) -join "") -match "uid=0"
$hasData = ((Adb @("shell", "su -c 'ls -d /data/data/$Pkg'")) -join "") -match "/data/data/"

if (-not $Wipe -and $hasRoot -and $hasData) {
    Write-Host "[2/6] 备份存档 -> $tar" -ForegroundColor Cyan
    Adb @("shell", "su -c 'rm -f $tar; tar -cf $tar -C /data/data $Pkg'") | Out-Null
    $sz = ((Adb @("shell", "su -c 'stat -c %s $tar'")) -join "").Trim()
    Write-Host "      备份大小 $sz 字节"
    if ($sz -notmatch '^\d+$' -or [int64]$sz -lt 1024) {
        throw "备份失败，已中止（不敢卸了）。要强装用 -Wipe，但存档会没。"
    }
} else {
    if ($Wipe) {
        Write-Host "[2/6] -Wipe：不备份，装完是全新存档" -ForegroundColor Yellow
    } else {
        Write-Host "[2/6] 无 root 或没有数据目录，跳过备份" -ForegroundColor Yellow
        Write-Host "      注意：接下来 pm uninstall 会连存档一起删！" -ForegroundColor Red
        $ans = Read-Host "继续？(y/N)"
        if ($ans -ne "y") { throw "已取消" }
    }
}

Write-Host "[3/6] 卸载旧包（会删数据目录）" -ForegroundColor Cyan
Adb @("shell", "pm uninstall $Pkg") | Out-Null

Write-Host "[4/6] 推送 + 安装" -ForegroundColor Cyan
Adb @("push", $Apk, $remote) | Out-Null
$r = Adb @("shell", "pm install $remote")
$r | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" }
if (($r -join "`n") -match "Failure") { throw "安装失败" }
Adb @("shell", "rm -f $remote") | Out-Null

if (-not $Wipe -and $hasRoot -and $hasData) {
    Write-Host "[5/6] 灌回存档" -ForegroundColor Cyan
    $uid = ((Adb @("shell", "su -c 'stat -c %u /data/data/$Pkg'")) -join "").Trim()
    Adb @("shell", "su -c 'am force-stop $Pkg'") | Out-Null
    Adb @("shell", "su -c 'tar -xf $tar -C /data/data'") | Out-Null
    Adb @("shell", "su -c 'chown -R $uid`:$uid /data/data/$Pkg'") | Out-Null
    Adb @("shell", "su -c 'restorecon -R /data/data/$Pkg'") | Out-Null
    Write-Host "      uid=$uid"
} else {
    Write-Host "[5/6] 跳过存档恢复" -ForegroundColor Cyan
}

Write-Host "[6/6] 启动" -ForegroundColor Cyan
Adb @("shell", "monkey -p $Pkg -c android.intent.category.LAUNCHER 1") | Out-Null

Write-Host ""
Write-Host "装好了。开游戏后小圆球可以拖到屏幕任意位置。" -ForegroundColor Green
