# tlw_multi.ps1 - manage FPS unlock across multiple MuMu instances
#
# Scans all adb devices, detects which server each one runs (Global/JP/CN),
# applies the FPS setting and starts the guard on every device that has the game.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tlw_multi.ps1 -Fps 165
#   powershell -ExecutionPolicy Bypass -File tlw_multi.ps1 -Fps 165 -Status
#   powershell -ExecutionPolicy Bypass -File tlw_multi.ps1 -Stop

param(
    [int]$Fps = 0,
    [switch]$Status,
    [switch]$Stop,
    [switch]$Restore,
    [string]$Adb = "",
    [string]$Dir = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'

# ---- locate adb ----
if (-not $Adb) {
    $candidates = @(
        (Join-Path $Dir "adb\adb.exe"),
        "D:\adb\adb.exe",
        (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"),
        "C:\adb\adb.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $Adb = $c; break }
    }
    if (-not $Adb) {
        $found = Get-Command adb -ErrorAction SilentlyContinue
        if ($found) { $Adb = "adb" }
    }
}
if (-not $Adb) {
    Write-Host "[x] adb not found" -ForegroundColor Red
    exit 1
}

function Run-Adb {
    param([string]$Dev, [string[]]$Cmd)
    $all = @('-s', $Dev) + $Cmd
    $p = & $Adb @all 2>&1
    return ($p | Out-String).Trim()
}

# ---- ensure root on a device ----
# tries adb root first, falls back to checking su
# returns: "direct" (adb root works), "su" (needs su -c), or "none"
function Get-RootMode {
    param([string]$Dev)

    # already root?
    $id = Run-Adb -Dev $Dev -Cmd @('shell', 'id')
    if ($id -match 'uid=0') { return 'direct' }

    # try su FIRST - safer, some emulators (LDPlayer 9) crash adbd on 'adb root'
    $suId = Run-Adb -Dev $Dev -Cmd @('shell', 'su -c id')
    if ($suId -match 'uid=0') { return 'su' }

    # only as a last resort try adb root
    # adb root restarts adbd, so the device goes offline briefly. With two
    # MuMu 15 instances the restart windows can overlap, so wait longer and
    # retry instead of trusting a single check.
    Run-Adb -Dev $Dev -Cmd @('root') | Out-Null
    Start-Sleep -Milliseconds 2000
    Run-Adb -Dev $Dev -Cmd @('wait-for-device') | Out-Null
    for ($i = 0; $i -lt 6; $i++) {
        $id = Run-Adb -Dev $Dev -Cmd @('shell', 'id')
        if ($id -match 'uid=0') { return 'direct' }
        Start-Sleep -Milliseconds 500
    }

    return 'none'
}

# ---- run a command with the right privilege ----
function Run-Root {
    param([string]$Dev, [string]$RootMode, [string]$Cmd)
    if ($RootMode -eq 'direct') {
        return Run-Adb -Dev $Dev -Cmd @('shell', $Cmd)
    } elseif ($RootMode -eq 'su') {
        # Device-side sh re-parses the command, so double quotes get eaten
        # twice (PowerShell then adb/sh). Single quotes survive both layers
        # and reach su intact - without them su sees 'su -c sh /path' and
        # reports 'Unknown id: /path'.
        $escaped = $Cmd.Replace("'", "'\''")
        return Run-Adb -Dev $Dev -Cmd @('shell', "su -c '$escaped'")
    }
    return ''
}


# ---- collect ports to try ----
$ports = New-Object System.Collections.Generic.HashSet[int]

# 1. read ports from MuMu config files (works for any number of instances)
$mumuRoots = @(
    "E:\MuMu Player 12\vms",
    "C:\Program Files\Netease\MuMuPlayer-12.0\vms",
    (Join-Path $env:USERPROFILE "MuMuPlayer-12.0\vms")
)
foreach ($root in $mumuRoots) {
    if (-not (Test-Path $root)) { continue }
    foreach ($vmDir in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue) {
        $cfg = Join-Path $vmDir.FullName "configs\vm_config.json"
        if (-not (Test-Path $cfg)) { continue }
        try {
            $raw = Get-Content $cfg -Raw -ErrorAction Stop
            $m = [regex]::Match($raw, '"adb"\s*:\s*\{[^}]*"host_port"\s*:\s*"(\d+)"')
            if ($m.Success) {
                $pt = [int]$m.Groups[1].Value
                [void]$ports.Add($pt)
            }
        } catch { }
    }
}

# 2. fallback ports for MuMu (16xxx) and LDPlayer (5555+)
foreach ($p in @(16480, 16512, 16384, 16416, 16448, 16464, 16496, 16528,
                 7555, 7556, 7557, 7558,
                 5555, 5556, 5557, 5558)) {
    [void]$ports.Add($p)
}

Write-Host "[*] trying $($ports.Count) ports..." -ForegroundColor DarkGray
foreach ($p in $ports) {
    & $Adb connect "127.0.0.1:$p" 2>&1 | Out-Null
}
Start-Sleep -Milliseconds 800

$devices = @()
$lines = & $Adb devices 2>&1
foreach ($l in $lines) {
    if ($l -match '^(\S+)\s+device') {
        $devices += $matches[1]
    }
}
if ($devices.Count -eq 0) {
    Write-Host "[x] no devices found" -ForegroundColor Red
    exit 1
}

# dedupe by boot_id (same instance may listen on two ports)
$seen = @{}
$uniq = @()
foreach ($d in $devices) {
    $bid = Run-Adb -Dev $d -Cmd @('shell', 'cat /proc/sys/kernel/random/boot_id')
    if (-not $seen.ContainsKey($bid)) {
        $seen[$bid] = $true
        $uniq += $d
    }
}
$devices = $uniq

Write-Host ""
Write-Host "=== Devices ===" -ForegroundColor Cyan
foreach ($d in $devices) {
    Write-Host "  $d"
}
Write-Host ""

# ---- push scripts and query each device ----
$scripts = @('tlw_common.sh', 'tlw_fps.sh', 'tlw_guard.sh', 'tlw_info.sh')
$results = @()
$rootModes = @{}

foreach ($d in $devices) {
    # ensure root
    $rm = Get-RootMode -Dev $d
    if ($rm -eq 'none') {
        Write-Host "[!] $d : no root, skipping" -ForegroundColor Red
        continue
    }
    $rootModes[$d] = $rm

    # push
    $pushed = $true
    foreach ($s in $scripts) {
        $src = Join-Path $Dir $s
        if (-not (Test-Path $src)) { $pushed = $false; continue }
        & $Adb -s $d push $src "/data/local/tmp/$s" 2>&1 | Out-Null
    }
    if (-not $pushed) {
        Write-Host "[!] $d : scripts missing" -ForegroundColor Yellow
        continue
    }
    Run-Adb -Dev $d -Cmd @('shell', 'chmod 755 /data/local/tmp/tlw_*.sh') | Out-Null

    # info
    $info = Run-Root -Dev $d -RootMode $rm -Cmd 'sh /data/local/tmp/tlw_info.sh'
    $parts = $info -split '\|'
    if ($parts.Count -lt 4) {
        Write-Host "[!] $d : bad info output: $info" -ForegroundColor Yellow
        continue
    }

    # get package name for this device
    $pkgName = Run-Adb -Dev $d -Cmd @('shell', 'sh /data/local/tmp/tlw_common.sh 2>/dev/null; pm list packages | grep -oE "(jp\\.goodsmile\\.touhoulostword[a-z_]*|com\\.gg\\.touhoulw)" | head -1')
    if (-not $pkgName) {
        $pkgName = Run-Adb -Dev $d -Cmd @('shell', 'pm list packages | grep -iE "touhou" | head -1 | sed "s/package://"')
    }

    $results += [PSCustomObject]@{
        Device = $d
        Server = $parts[0]
        Version = $parts[1]
        RunState = $parts[2]
        Fps = $parts[3]
        Pkg = $pkgName
        RootMode = $rm
    }
}

# ---- show status ----
Write-Host "=== Status ===" -ForegroundColor Cyan
Write-Host ("{0,-22} {1,-8} {2,-8} {3,-10} {4}" -f "Device", "Server", "Version", "RunState", "FPS")
Write-Host ("-" * 65)
foreach ($r in $results) {
    $color = if ($r.Server -eq 'none') { 'DarkGray' } else { 'White' }
    Write-Host ("{0,-22} {1,-8} {2,-8} {3,-10} {4}" -f $r.Device, $r.Server, $r.Version, $r.RunState, $r.Fps) -ForegroundColor $color
}
Write-Host ""

if ($Status) { exit 0 }

# ---- stop ----
if ($Stop) {
    foreach ($r in $results) {
        $out = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd 'sh /data/local/tmp/tlw_guard.sh stop'
        Write-Host "$($r.Device) ($($r.Server)): $out"
    }
    exit 0
}

# ---- restore ----
if ($Restore) {
    Write-Host "=== Restoring all devices ===" -ForegroundColor Cyan
    foreach ($r in $results) {
        if ($r.Server -eq 'none') { continue }
        Write-Host "  $($r.Device) ($($r.Server))" -ForegroundColor White

        # stop guard first
        $stopOut = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd 'sh /data/local/tmp/tlw_guard.sh stop'
        Write-Host "    $stopOut"

        # set fps to 0 (follow display)
        $setOut = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd 'sh /data/local/tmp/tlw_fps.sh 0'
        Write-Host "    $setOut"
    }

    Write-Host ""
    Write-Host "=== Final check ===" -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    foreach ($r in $results) {
        if ($r.Server -eq 'none') { continue }
        $info = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd 'sh /data/local/tmp/tlw_info.sh'
        Write-Host "  $($r.Device): $info"
    }
    exit 0
}


# ---- detect fps offset for a device ----
# returns offset string like "0x199cc54" or $null
function Get-FpsOffset {
    param([string]$Dev, [string]$Pkg, [string]$Ver)

    # 1. ask the device first (cached or known table)
    $cached = Run-Adb -Dev $Dev -Cmd @('shell', "sh /data/local/tmp/tlw_fps.sh detect 2>/dev/null | grep -o '0x[0-9a-f]*' | head -1")
    if ($cached -match '^0x[0-9a-f]+$') {
        return $cached
    }

    # 2. unknown version - extract libunity.so and scan on PC
    Write-Host "    [*] version $Ver unknown, extracting libunity.so..." -ForegroundColor Yellow
    Run-Adb -Dev $Dev -Cmd @('shell', 'rm -rf /data/local/tmp/tlw_d; mkdir -p /data/local/tmp/tlw_d') | Out-Null
    Run-Adb -Dev $Dev -Cmd @('shell', "for p in `$(pm path $Pkg | sed s/package://); do unzip -o `$p 'lib/*/libunity.so' -d /data/local/tmp/tlw_d 2>/dev/null; done") | Out-Null

    $remotePath = Run-Adb -Dev $Dev -Cmd @('shell', 'find /data/local/tmp/tlw_d -name libunity.so | head -1')
    if (-not $remotePath) {
        Write-Host "    [x] cannot extract libunity.so" -ForegroundColor Red
        return $null
    }

    $localDump = Join-Path $env:TEMP ("tlw_lib_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".so")
    & $Adb -s $Dev pull $remotePath $localDump 2>&1 | Out-Null
    Run-Adb -Dev $Dev -Cmd @('shell', 'rm -rf /data/local/tmp/tlw_d') | Out-Null

    if (-not (Test-Path $localDump)) {
        Write-Host "    [x] pull failed" -ForegroundColor Red
        return $null
    }

    $scanner = Join-Path $Dir "tlw_elf_scan.ps1"
    if (-not (Test-Path $scanner)) {
        Write-Host "    [x] tlw_elf_scan.ps1 missing" -ForegroundColor Red
        Remove-Item $localDump -Force -ErrorAction SilentlyContinue
        return $null
    }

    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $scanner $localDump 2>&1
    Remove-Item $localDump -Force -ErrorAction SilentlyContinue

    $off = $null
    foreach ($line in $out) {
        if ("$line" -match '^(0x[0-9a-f]+)$') {
            $off = $matches[1]
        }
    }

    if ($off) {
        Write-Host "    [+] detected offset: $off" -ForegroundColor Green
        # cache it on device
        Run-Adb -Dev $Dev -Cmd @('shell', "echo '$Pkg $off' > /data/local/tmp/tlw_fps_offset.txt") | Out-Null
        return $off
    }

    Write-Host "    [x] detection failed" -ForegroundColor Red
    return $null
}

# ---- apply fps ----
if ($Fps -lt 1) {
    Write-Host "[!] specify -Fps <number> to apply, or -Status / -Stop" -ForegroundColor Yellow
    exit 0
}

Write-Host "=== Applying $Fps fps ===" -ForegroundColor Cyan
foreach ($r in $results) {
    if ($r.Server -eq 'none') {
        Write-Host "  $($r.Device) : no game, skip" -ForegroundColor DarkGray
        continue
    }
    if ($r.RunState -eq 'stopped') {
        Write-Host "  $($r.Device) ($($r.Server)) : game not running, setting will apply on next launch" -ForegroundColor Yellow
    }

    Write-Host "  $($r.Device) ($($r.Server) v$($r.Version))" -ForegroundColor White

    # ensure offset is known for this device
    $off = Get-FpsOffset -Dev $r.Device -Pkg $r.Pkg -Ver $r.Version
    if (-not $off) {
        Write-Host "    [x] cannot determine offset, skipping this device" -ForegroundColor Red
        continue
    }

    $set = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd "sh /data/local/tmp/tlw_fps.sh $Fps"
    $guard = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd "sh /data/local/tmp/tlw_guard.sh start $Fps"

    Write-Host "    $set"
    Write-Host "    $guard"
}

Write-Host ""
Write-Host "=== Final check ===" -ForegroundColor Cyan
Start-Sleep -Seconds 2
foreach ($r in $results) {
    if ($r.Server -eq 'none') { continue }
    $info = Run-Root -Dev $r.Device -RootMode $r.RootMode -Cmd 'sh /data/local/tmp/tlw_info.sh'
    Write-Host "  $($r.Device): $info"
}
