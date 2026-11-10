#requires -Version 7
<#
.SYNOPSIS
  启动/等待 Android 模拟器（默认 Medium_Phone），等待 boot_completed，断网并输出设备摘要。

.DESCRIPTION
  可复用：阶段 2 直接 `pwsh -File work\device\boot.ps1` 即可（已有设备则跳过启动）。
  启动参数: -avd Medium_Phone -no-snapshot-save -no-boot-anim -no-audio -gpu swiftshader_indirect
  若 swiftshader 起不来，可用 -Gpu host 或 -Gpu angle_indirect 重试。

.EXAMPLE
  pwsh -File work\device\boot.ps1
  pwsh -File work\device\boot.ps1 -Avd Medium_Phone -BootTimeoutSec 420 -Gpu host -NoStart
#>
param(
    [string]$Avd = 'Medium_Phone',
    [int]$BootTimeoutSec = 420,
    [string]$Gpu = 'swiftshader_indirect',
    [switch]$NoStart,
    [switch]$SkipNetOff
)
$ErrorActionPreference = 'Stop'
$adb = 'D:\Android\SDK\platform-tools\adb.exe'
$emulator = 'D:\Android\SDK\emulator\emulator.exe'
$devDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$emulatorLog = Join-Path $devDir 'emulator.log'
$netOffSh = Join-Path $devDir 'net-off.sh'

function Get-OnlineSerial {
    foreach ($line in (& $adb devices 2>$null)) {
        if ($line -match '^(emulator-\d+)\s+device\b') { return $Matches[1] }
    }
    return $null
}

function Start-EmulatorIfNeeded {
    if (Get-OnlineSerial) { Write-Host '[boot] 已有在线设备，跳过启动'; return }
    if ($NoStart) { throw '[boot] 没有在线设备且指定了 -NoStart' }
    if (Test-Path $emulatorLog) { Remove-Item $emulatorLog -Force }
    $cmdArgs = '"/c ""' + $emulator + '" -avd ' + $Avd + ' -no-snapshot-save -no-boot-anim -no-audio -gpu ' + $Gpu + ' > ""' + $emulatorLog + '"" 2>&1""'
    Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -WindowStyle Hidden
    Write-Host "[boot] 已后台启动模拟器 $Avd，gpu=$Gpu，日志: $emulatorLog"
}

function Wait-Boot([int]$TimeoutSec) {
    Write-Host "[boot] 等待设备上线 + sys.boot_completed=1（超时 ${TimeoutSec}s）..."
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $serial = Get-OnlineSerial
        if ($serial) {
            $booted = (& $adb shell getprop sys.boot_completed 2>$null) -join ''
            if ($booted.Trim() -eq '1') {
                # 等 PackageManager 就绪，否则 pm/am 可能报错
                for ($i = 0; $i -lt 20; $i++) {
                    $pmReady = (& $adb shell pm path android 2>$null) -join ''
                    if ($pmReady -match 'package:') { break }
                    Start-Sleep -Seconds 2
                }
                return $serial
            }
        }
        Start-Sleep -Seconds 3
    }
    throw "[boot] 等待 boot_completed 超时（${TimeoutSec}s）。请查看 $emulatorLog，或换 -Gpu host / -Gpu angle_indirect 重试"
}

function Disable-Network {
    if ($SkipNetOff) { Write-Host '[net] 已指定 -SkipNetOff，跳过断网'; return 'skipped' }
    Write-Host '[net] 断网（wifi/data/飞行模式）...'
    & $adb push $netOffSh /data/local/tmp/net-off.sh | Out-Null
    $out = (& $adb shell sh /data/local/tmp/net-off.sh 2>&1) -join "`n"
    Write-Host $out
    return $out
}

function Show-Summary {
    Write-Host ''
    Write-Host '================ 设备摘要 ================'
    $props = & $adb shell getprop 2>$null
    foreach ($key in @('ro.build.version.release', 'ro.build.version.sdk', 'ro.build.version.sdk_full',
                       'ro.product.cpu.abi', 'ro.product.cpu.abilist', 'ro.build.type', 'ro.debuggable',
                       'ro.dalvik.vm.native.bridge', 'ro.kernel.qemu')) {
        $v = ($props | Select-String -SimpleMatch "[$key]:") -join ''
        if ($v) { Write-Host $v.Trim() }
    }
    Write-Host ("page_size={0}" -f ((& $adb shell getconf PAGESIZE 2>$null) -join '').Trim())
    Write-Host '--- df /data /sdcard ---'
    & $adb shell df -h /data /sdcard 2>&1 | ForEach-Object { Write-Host $_ }
    Write-Host '--- 已安装 TLW 相关包 ---'
    $found = (& $adb shell pm list packages 2>$null) | Select-String 'goodsmile|touhou|tlw'
    if ($found) { $found | ForEach-Object { Write-Host $_.Line.Trim() } } else { Write-Host '(无)' }
    Write-Host '=========================================='
}

try {
    Start-EmulatorIfNeeded
    $serial = Wait-Boot $BootTimeoutSec
    Write-Host "[boot] 设备在线: $serial"
    $net = Disable-Network
    Show-Summary
    Write-Host '[boot] OK'
} catch {
    Write-Error $_
    exit 1
}
