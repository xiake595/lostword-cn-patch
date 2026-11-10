#requires -Version 7
<#
.SYNOPSIS
  收集设备侧证据（安装/启动/解包验证相关），保存到 work\device\evidence\pull-<tag>\。

.DESCRIPTION
  无 root 环境下可验证：外部目录 /sdcard/Android/data/<pkg>/files 的 UnityCache/Shared 文件数、
  tlw_cn 钩子目录内容、包信息、磁盘统计、logcat、当前截图。
  内部 /data/data/<pkg>（master cache 84 文件、marker）普通 shell 不可读 —— 依赖 TlwCn 应用日志，
  以及 dumpsys diskstats 的聚合数据大小。

.EXAMPLE
  pwsh -File work\device\pull-evidence.ps1 -Tag final-cn
#>
param(
    [string]$Package = 'jp.goodsmile.touhoulostwordglobal_android',
    [string]$Tag = ('pull-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [switch]$ForceStop
)
$ErrorActionPreference = 'Stop'
$adb = 'D:\Android\SDK\platform-tools\adb.exe'
$devDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evDir = Join-Path $devDir 'evidence'
$outDir = Join-Path $evDir "pull-$Tag"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$extBase = "/sdcard/Android/data/$Package/files"

function Save-Adb([string]$name, [string]$command) {
    $p = Join-Path $outDir $name
    & $adb shell $command 2>&1 | Out-File -FilePath $p -Encoding utf8
    return $p
}

Write-Host "收集证据到 $outDir"
# 1) 设备/包信息
Save-Adb 'device-info.txt' 'getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.cpu.abilist; getprop ro.build.type; getprop ro.debuggable; getprop ro.dalvik.vm.native.bridge; getconf PAGESIZE; df -h /data /sdcard; wm size; settings get global airplane_mode_on' | Out-Null
Save-Adb 'package-info.txt' "dumpsys package $Package" | Out-Null
Save-Adb 'diskstats.txt' 'dumpsys diskstats' | Out-Null
# 2) 外部数据目录（解包结果主要落点）
Save-Adb 'external-tree.txt' "du -sh $extBase 2>/dev/null; echo ---; find $extBase -maxdepth 4 2>/dev/null | head -n 80" | Out-Null
Save-Adb 'external-counts.txt' "echo -n 'UnityCache/Shared __data count: '; find $extBase/UnityCache/Shared -name __data 2>/dev/null | wc -l; echo -n 'UnityCache/Shared total bytes: '; du -sb $extBase/UnityCache/Shared 2>/dev/null | cut -f1; echo -n 'UnityCache dirs: '; find $extBase/UnityCache/Shared -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l; echo '--- tlw_cn ---'; ls -la $extBase/tlw_cn 2>/dev/null" | Out-Null
# 3) logcat 与截图
& $adb logcat -d -v threadtime 2>&1 | Out-File -FilePath (Join-Path $outDir 'logcat.txt') -Encoding utf8
Get-Content (Join-Path $outDir 'logcat.txt') |
    Select-String -Pattern "$([regex]::Escape($Package))|TlwFps|TlwCn|FATAL|AndroidRuntime|Unity|Bugsnag|Displayed" |
    Out-File -FilePath (Join-Path $outDir 'logcat-app.txt') -Encoding utf8
cmd /c "`"$adb`" exec-out screencap -p > `"$(Join-Path $outDir 'screenshot.png')`""
# 4) 若当前前台是游戏，记录 Activity 栈
Save-Adb 'activity-stack.txt' "dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity|$([regex]::Escape($Package))' | head -n 20" | Out-Null

if ($ForceStop) {
    Write-Host 'force-stop...'
    & $adb shell am force-stop $Package 2>&1 | Out-Null
}

Write-Host ''
Write-Host '--- 摘要 ---'
Get-Content (Join-Path $outDir 'external-counts.txt') -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
Write-Host ("外部目录总大小: " + ((& $adb shell du -sh $extBase 2>&1) -join '').Trim())
Write-Host ''
Get-ChildItem $outDir | Select-Object Name, Length | Format-Table -AutoSize
