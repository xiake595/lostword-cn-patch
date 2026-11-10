# build.ps1 -- build the patched Touhou LostWord (global) APK
#
# Patch set, applied to the ORIGINAL apk without re-encoding resources:
#   1. classes3.dex      -> tlw.fps.* (compiled here)
#   2. AndroidManifest   -> one <provider> injected (binary AXML edit)
#   3. everything else   -> copied byte-for-byte, compression preserved
#   4. lib/arm64-v8a/*   -> merged in from the ABI split, so the result installs
#                           as ONE standalone APK (no split install, no adb)
#
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1

param(
    [string]$BaseApk  = "apk\base.apk",
    [string]$SplitApk = "apk\split_arm64.apk",
    [string]$Manifest = "orig\AndroidManifest.xml",
    [string]$Activity = "com.google.firebase.MessagingUnityPlayerActivity",
    [string]$OldPkg   = "jp.goodsmile.touhoulostwordglobal_android",
    [string]$OldLabel = "Touhou LostWord",
    [string]$Authority = "tlw.fps.boot",
    [string]$Pkg      = "",
    [string]$Label    = "",
    [string]$Icon     = "assets\tlw_icon.png",
    [string]$Out      = "out\TLW-global-1.57.0-fps.apk",
    [string]$JdkHome  = $env:JAVA_HOME,
    [string]$SdkRoot  = $env:ANDROID_SDK_ROOT,
    [string]$PythonExe = "python",
    [string]$R8Jar = "r8.jar",
    [string]$KeyStore = "tlw-release.jks",
    [string]$KeyAlias = "tlw"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not $SdkRoot) { $SdkRoot = $env:ANDROID_HOME }
if (-not $JdkHome) { throw "Pass -JdkHome or set JAVA_HOME." }
if (-not $SdkRoot) { throw "Pass -SdkRoot or set ANDROID_SDK_ROOT." }
$java = Join-Path $JdkHome "bin\java.exe"
$javac = Join-Path $JdkHome "bin\javac.exe"
$r8 = $R8Jar
$bt = (Get-ChildItem (Join-Path $SdkRoot "build-tools") -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "apksigner.bat") } |
    Sort-Object { [version]($_.Name -replace '-.*$', '') } -Descending | Select-Object -First 1).FullName
$aj = (Get-ChildItem (Join-Path $SdkRoot "platforms") -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "android.jar") } |
    Sort-Object { [int](($_.Name -replace '^android-', '') -replace '\..*$', '') } -Descending | Select-Object -First 1).FullName
if (-not $bt -or -not $aj) { throw "Android build-tools/platform not found." }
$aj = Join-Path $aj "android.jar"
$python = $PythonExe
$ks = $KeyStore
if (-not $env:TLW_KEYSTORE_PASSWORD) { throw "Set TLW_KEYSTORE_PASSWORD before building." }
foreach ($inputFile in @($java, $javac, $r8, $ks, $BaseApk, $SplitApk)) {
    if (-not (Test-Path $inputFile)) { throw "Missing required input: $inputFile" }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Manifest) | Out-Null

function Step($n, $msg) { Write-Host "[$n/6] $msg" -ForegroundColor Cyan }

Step 1 "javac tlw.fps"
Remove-Item -Recurse -Force "build\classes","build\dexout" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "build\classes","build\dexout" | Out-Null
$srcs = Get-ChildItem "src\tlw\fps\*.java" | ForEach-Object { $_.FullName }
& $javac -source 8 -target 8 -g:none -nowarn -Xlint:-options -XDstringConcat=inline -bootclasspath $aj -d "build\classes" -encoding UTF-8 $srcs
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

Step 2 "d8"
$classes = Get-ChildItem "build\classes\tlw\fps\*.class" | ForEach-Object { $_.FullName }
& $java -cp $r8 com.android.tools.r8.D8 --release --min-api 24 --lib $aj --output "build\dexout" $classes
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

Step 3 "manifest"
# Always take the manifest out of the base APK that is about to be patched.
# Reusing a stale orig\AndroidManifest.xml next to a new base.apk is the classic
# way to ship an APK whose manifest no longer matches its dex/resources.
$manifestFrom = "build\AndroidManifest.orig.xml"
& $python -c "import zipfile,sys;open(sys.argv[2],'wb').write(zipfile.ZipFile(sys.argv[1]).read('AndroidManifest.xml'))" $BaseApk $manifestFrom
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $manifestFrom)) {
    if (Test-Path $Manifest) {
        $manifestFrom = $Manifest
        Write-Host "      (fallback) using $Manifest" -ForegroundColor DarkYellow
    } else {
        throw "cannot read AndroidManifest.xml from $BaseApk"
    }
} else {
    Write-Host "      source: AndroidManifest.xml from $BaseApk"
    Copy-Item $manifestFrom $Manifest -Force
}

& $python "tools\axml.py" add-provider $manifestFrom "build\AndroidManifest.p.xml" "tlw.fps.TlwBoot" $Authority
if ($LASTEXITCODE -ne 0) { throw "provider injection failed" }
& $python "tools\axml.py" add-perm "build\AndroidManifest.p.xml" "build\AndroidManifest.q.xml" android.permission.SYSTEM_ALERT_WINDOW
if ($LASTEXITCODE -ne 0) { throw "permission add failed" }
& $python "tools\axml.py" drop-attr "build\AndroidManifest.q.xml" "build\AndroidManifest.s.xml" manifest requiredSplitTypes manifest splitTypes
if ($LASTEXITCODE -ne 0) { throw "split-attr drop failed" }

# The game ships hardwareAccelerated="false" on its Unity activity, so the whole
# window -- our overlay included -- is rasterised on the CPU. Turning it on gives
# the overlay a GPU-composited surface, which is what makes dragging smooth.
# If a new version renames the launcher activity this silently patches nothing
# and dragging goes back to CPU rasterisation, so the result is checked.
$hw = & $python "tools\axml.py" set-bool "build\AndroidManifest.s.xml" "build\AndroidManifest.xml" "activity@android:name=$Activity" hardwareAccelerated true 2>&1
$hw | ForEach-Object { Write-Host "      $_" }
if ($LASTEXITCODE -ne 0) { throw "hw-accel patch failed" }
if (($hw -join "`n") -notmatch "total changed: 1") {
    throw "hardwareAccelerated did not land on any activity -- the launcher activity is no longer '$Activity'. Re-run with -Activity <new name> (check `aapt dump badging`)."
}

# Optional: side-by-side build. Renames the app so it installs NEXT TO the
# official client instead of replacing it. Everything is patched in place with a
# same-length string, so resources.arsc is never re-encoded.
$manifestP = "build\AndroidManifest.xml"
$arscPath  = $null
if ($Pkg -ne "") {
    Step "3b" "clone package"
    if ($Pkg.Length -ne $OldPkg.Length) {
        throw "-Pkg must be exactly $($OldPkg.Length) characters (byte-for-byte patch), got $($Pkg.Length)"
    }
    $arscOrig = "build\resources.orig.arsc"
    & $python -c "import zipfile,sys;open(sys.argv[2],'wb').write(zipfile.ZipFile(sys.argv[1]).read('resources.arsc'))" $BaseApk $arscOrig
    if ($LASTEXITCODE -ne 0) { throw "cannot read resources.arsc from $BaseApk" }
    if ($Label -ne "") {
        & $python "tools\clone.py" "build\AndroidManifest.xml" "build\AndroidManifest.clone.xml" $arscOrig "build\resources.clone.arsc" $OldPkg $Pkg $OldLabel $Label
    } else {
        & $python "tools\clone.py" "build\AndroidManifest.xml" "build\AndroidManifest.clone.xml" $arscOrig "build\resources.clone.arsc" $OldPkg $Pkg
    }
    if ($LASTEXITCODE -ne 0) { throw "package rename failed" }
    $manifestP = "build\AndroidManifest.clone.xml"
    $arscPath  = "build\resources.clone.arsc"
}

Step 4 "repack"
$icon = $Icon
$repack = @($BaseApk, $SplitApk, $manifestP, "build\dexout\classes.dex", "build\unaligned.apk")
if ($icon -ne "" -and (Test-Path $icon)) {
    Write-Host "      icon: $icon"
    $repack += $icon
} else {
    Write-Host "      icon: (none, using the drawn badge)" -ForegroundColor DarkGray
}
if ($arscPath) {
    Write-Host "      arsc: $arscPath (patched package name)"
    $repack += @("-arsc", $arscPath)
}
& $python "tools\repack.py" @repack
if ($LASTEXITCODE -ne 0) { throw "repack failed" }

Step 5 "zipalign"
Remove-Item "build\aligned.apk" -ErrorAction SilentlyContinue
& "$bt\zipalign.exe" -p -f 4 "build\unaligned.apk" "build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

Step 6 "apksigner"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
Remove-Item $Out -ErrorAction SilentlyContinue
& "$bt\apksigner.bat" sign --ks $ks --ks-pass env:TLW_KEYSTORE_PASSWORD --key-pass env:TLW_KEYSTORE_PASSWORD --ks-key-alias $KeyAlias --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --out $Out "build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }

& "$bt\apksigner.bat" verify --print-certs $Out | Select-Object -First 2

$mb = [math]::Round((Get-Item $Out).Length / 1MB, 1)
Write-Host ""
Write-Host "OK -> $Out ($mb MB)" -ForegroundColor Green
