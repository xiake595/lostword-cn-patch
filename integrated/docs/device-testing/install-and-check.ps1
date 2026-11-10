#requires -Version 7
<#
.SYNOPSIS
  安装 APK → 断网 → 启动 → 观察 N 秒 → 抓 logcat/截图 → 判定不闪退 → force-stop。

.DESCRIPTION
  只验证「能安装 + 能启动且不立即闪退」，全程保持断网；不要点登录/进入游戏。
  可复用：阶段 2 只改 -Apk 即可。
  - 安装默认用 `adb install -r`（升级、保留数据）。安装失败绝不卸载/清数据，只报告。
  - 自动点掉已知系统弹窗：16KB 兼容提示(Don't Show Again)、沉浸全屏(Got it)、通知权限等。
  - 证据保存到 work\device\evidence\：<tag>-logcat.txt / <tag>-logcat-app.txt / <tag>-final.png 等。

.EXAMPLE
  pwsh -File work\device\install-and-check.ps1 -Apk 'D:\Codex_Project\Lostword\integrated\out\TLW-global-1.57.0-cn-fps.apk'
  pwsh -File work\device\install-and-check.ps1 -SkipInstall -ObserveSec 40 -Tag final-cn
#>
param(
    [string]$Apk = '',
    [string]$Package = 'jp.goodsmile.touhoulostwordglobal_android',
    [string]$Component = '',
    [int]$ObserveSec = 25,
    [switch]$SkipInstall,
    [switch]$FreshInstall,
    [switch]$KeepRunning,
    [string]$Tag = ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
)
$ErrorActionPreference = 'Stop'
$adb = 'D:\Android\SDK\platform-tools\adb.exe'
$devDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evDir = Join-Path $devDir 'evidence'
$netOffSh = Join-Path $devDir 'net-off.sh'
$workDir = Join-Path $devDir 'tmp'
New-Item -ItemType Directory -Force -Path $evDir, $workDir | Out-Null

$summary = [ordered]@{
    tag = $Tag; apk = $Apk; package = $Package
    install = ''; installSec = 0; dfBefore = ''; dfAfter = ''
    launcher = ''; pid = ''; alive = $false; fatalCount = 0
    dialogsDismissed = @(); screenshots = @(); logcat = ''; logcatApp = ''
}

function Write-Step([string]$msg) { Write-Host "== $msg" -ForegroundColor Cyan }

function Assert-Device {
    $d = (& $adb devices 2>$null) -join "`n"
    if ($d -notmatch 'emulator-\d+\s+device') { throw '没有在线模拟器；先运行 work\device\boot.ps1' }
}

function Disable-Network {
    & $adb push $netOffSh /data/local/tmp/net-off.sh 2>&1 | Out-Null
    $netOut = (& $adb shell sh /data/local/tmp/net-off.sh 2>&1) -join "`n"
    Write-Host $netOut
    if ($netOut -match 'Network is unreachable|Network unreachable|bad address') { return }
    if ($netOut -match 'airplane_mode_on=0') { Write-Warning '故障：飞行模式未打开，请检查' }
}

function Get-LauncherComponent {
    $raw = (& $adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $Package 2>&1) -join "`n"
    $m = [regex]::Match($raw, '([A-Za-z0-9_.]+)/([A-Za-z0-9_.$]+)')
    if ($m.Success) { return "$($m.Groups[1].Value)/$($m.Groups[2].Value)" }
    return ''
}

# 自动点掉系统弹窗（16KB 兼容 / 沉浸模式 / 权限）
function Dismiss-KnownDialogs {
    $xmlPath = Join-Path $workDir 'window_dump.xml'
    $targets = @('Don''t Show Again', 'Got it', 'Allow', 'While using the app', 'OK', '允许', '知道了', '确定')
    $tapped = @()
    for ($round = 0; $round -lt 3; $round++) {
        & $adb shell uiautomator dump /sdcard/window_dump.xml 2>&1 | Out-Null
        & $adb pull /sdcard/window_dump.xml $xmlPath 2>&1 | Out-Null
        if (-not (Test-Path $xmlPath)) { return $tapped }
        try { [xml]$xml = Get-Content -Raw -Encoding utf8 $xmlPath } catch { return $tapped }
        $hit = $false
        $nodes = $xml.SelectNodes('//node')
        foreach ($n in $nodes) {
            $text = [string]$n.text
            if (-not $text) { continue }
            if ($targets -notcontains $text) { continue }
            if ([string]$n.clickable -ne 'true') { continue }
            if ([string]$n.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { continue }
            $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
            $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
            & $adb shell input tap $x $y 2>&1 | Out-Null
            $tapped += "$text@($x,$y)"
            $hit = $true
            Start-Sleep -Milliseconds 800
            break
        }
        if (-not $hit) { return $tapped }
    }
    return $tapped
}

function Save-Screenshot([string]$name) {
    $path = Join-Path $evDir $name
    cmd /c "`"$adb`" exec-out screencap -p > `"$path`""
    if (Test-Path $path) { return $path }
    return ''
}

try {
    Assert-Device
    Disable-Network

    if (-not $SkipInstall) {
        if (-not $Apk -or -not (Test-Path $Apk)) { throw "APK 不存在: $Apk" }
        Write-Step ("安装 " + (Get-Item $Apk).Length + " bytes : $Apk")
        $summary.dfBefore = ((& $adb shell df -h /data 2>&1) -join "`n")
        $installArgs = @('install')
        if (-not $FreshInstall) { $installArgs += '-r' }
        $installArgs += $Apk
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $installOut = (& $adb @installArgs 2>&1) -join "`n"
        $sw.Stop()
        $summary.installSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $summary.install = if ($LASTEXITCODE -eq 0) { 'SUCCESS' } else { "FAILED(exit=$LASTEXITCODE) $installOut" }
        "install=$($summary.install) elapsed_s=$($summary.installSec)`n$installOut" |
            Out-File -FilePath (Join-Path $evDir "$Tag-install.txt") -Encoding utf8
        Write-Host $installOut
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] 安装失败（退出码 $LASTEXITCODE）。未做任何卸载/清数据，请人工判断签名冲突或空间问题。" -ForegroundColor Red
            exit 2
        }
        $summary.dfAfter = ((& $adb shell df -h /data 2>&1) -join "`n")
    }

    Write-Step '确认安装版本'
    (& $adb shell dumpsys package $Package 2>$null | Select-String -Pattern 'versionName|versionCode|lastUpdateTime|primaryCpuAbi') |
        ForEach-Object { Write-Host $_.Line.Trim() }

    Write-Step '启动应用（先 force-stop + 清 logcat）'
    & $adb logcat -c 2>&1 | Out-Null
    & $adb shell am force-stop $Package 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    $summary.launcher = if ($Component) { $Component } else { Get-LauncherComponent }
    Write-Host "launcher=$($summary.launcher)"
    if ($summary.launcher -match '/') {
        & $adb shell am start -W -n $summary.launcher 2>&1 | ForEach-Object { Write-Host $_ }
    } elseif ($summary.launcher) {
        & $adb shell am start -W -n "$Package/$($summary.launcher)" 2>&1 | ForEach-Object { Write-Host $_ }
    } else {
        & $adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 2>&1 | Select-Object -Last 2 | ForEach-Object { Write-Host $_ }
    }

    Write-Step "观察 $ObserveSec 秒（断网，不点登录/Game Start）"
    $startAt = Get-Date
    $deadCount = 0
    $crashed = $false
    $lastShot = $false
    $dialogsChecked = 0
    while (((Get-Date) - $startAt).TotalSeconds -lt $ObserveSec) {
        Start-Sleep -Seconds 2
        $elapsed = [int]((Get-Date) - $startAt).TotalSeconds
        $pidNow = ((& $adb shell pidof $Package 2>$null) -join '').Trim()
        if ($pidNow) { $summary.pid = $pidNow; $deadCount = 0 } else { $deadCount++; if ($deadCount -ge 2 -and -not $crashed) { $crashed = $true; Write-Warning "进程消失（闪退）t=${elapsed}s" } }
        # 在启动初期检查系统弹窗（16KB 兼容提示 / 沉浸提示 / 权限）
        if ($dialogsChecked -lt 3 -and $elapsed -ge 2 -and $elapsed -le 14) {
            $dialogsChecked++
            $tapped = Dismiss-KnownDialogs
            if ($tapped.Count -gt 0) { $summary.dialogsDismissed += $tapped; Write-Host ("[dialog] 点击: " + ($tapped -join ', ')) }
        }
        if ($elapsed -ge 6 -and -not $lastShot) {
            $lastShot = $true
            $p = Save-Screenshot "$Tag-t6s.png"
            if ($p) { $summary.screenshots += $p }
        }
        Write-Host ("t={0,3}s pid={1,-8} alive={2}" -f $elapsed, $pidNow, [bool]$pidNow)
    }

    Write-Step '抓取 logcat 与最终截图'
    $logPath = Join-Path $evDir "$Tag-logcat.txt"
    & $adb logcat -d -v threadtime 2>&1 | Out-File -FilePath $logPath -Encoding utf8
    $appPath = Join-Path $evDir "$Tag-logcat-app.txt"
    $pidRe = if ($summary.pid) { $summary.pid } else { 'NO_PID' }
    Get-Content $logPath |
        Select-String -Pattern "\b$pidRe\b|$([regex]::Escape($Package))|TlwFps|TlwCn|AndroidRuntime|FATAL|Unity|Bugsnag|Displayed" |
        Out-File -FilePath $appPath -Encoding utf8
    $summary.logcat = $logPath
    $summary.logcatApp = $appPath

    $fatalLines = Get-Content $logPath | Select-String -Pattern ('FATAL EXCEPTION|Process: ' + [regex]::Escape($Package))
    $summary.fatalCount = @($fatalLines).Count
    $p = Save-Screenshot "$Tag-final.png"
    if ($p) { $summary.screenshots += $p }

    $pidEnd = ((& $adb shell pidof $Package 2>$null) -join '').Trim()
    $summary.pid = if ($pidEnd) { $pidEnd } else { $summary.pid }
    $summary.alive = [bool]$pidEnd -and -not $crashed
    $focus = ((& $adb shell dumpsys window 2>$null | Select-String 'mCurrentFocus' | Select-Object -First 1) -join '').Trim()

    if (-not $KeepRunning) {
        Write-Step 'force-stop（防止游戏继续跑/触发下载）'
        & $adb shell am force-stop $Package 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }
    $summary.dfAfter = ((& $adb shell df -h /data 2>&1) -join "`n")

    Write-Host ''
    Write-Host '================= 结果 ================='
    Write-Host ("安装: {0}  ({1}s)" -f $summary.install, $summary.installSec)
    Write-Host ("启动组件: {0}" -f $summary.launcher)
    Write-Host ("进程: pid={0}  存活={1}  崩溃={2}" -f $summary.pid, $summary.alive, $crashed)
    Write-Host ("FATAL 计数: {0}" -f $summary.fatalCount)
    Write-Host ("当前焦点: {0}" -f $focus)
    Write-Host ("截图: {0}" -f ($summary.screenshots -join ', '))
    Write-Host ("logcat: {0}" -f $summary.logcat)
    Write-Host ("logcat(app): {0}" -f $summary.logcatApp)
    Write-Host ("弹窗处理: {0}" -f ($summary.dialogsDismissed -join '; '))
    $summary | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $evDir "$Tag-summary.json") -Encoding utf8
    Write-Host '========================================='
    if ($summary.alive -and $summary.fatalCount -eq 0) {
        Write-Host '[PASS] 能启动、进程存活、无 FATAL EXCEPTION' -ForegroundColor Green
        exit 0
    } else {
        Write-Host '[FAIL] 启动后进程不存活或存在 FATAL EXCEPTION，详见 logcat' -ForegroundColor Red
        exit 3
    }
} catch {
    Write-Error $_
    exit 1
}
