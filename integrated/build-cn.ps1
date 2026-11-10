# build-cn.ps1 -- build the integrated Touhou LostWord (global 1.57.0) APK
#
# Content of the ONE apk:
#   * FPS unlock overlay          (src\tlw\fps, ContentProvider boot)
#   * CN localization data v1.3   (assets\lwlocal.zip -> unpacked on first run
#                                  by tlw.cn.CnSetupActivity)
#
# File-level pipeline, exactly like build.ps1 of the FPS project:
#   - original package name / versionCode / application label are kept
#     (resources.arsc is never re-encoded)
#   - AndroidManifest.xml is edited as compiled AXML
#   - every other entry keeps its original compression method
#   - lib/arm64-v8a/* is merged in from the ABI split -> one standalone APK
#
# Usage: pwsh -File build-cn.ps1            (or powershell -ExecutionPolicy Bypass -File ...)

param(
    [string]$Out          = "out\TLW-global-1.57.0-cn-fps.apk",
    [string]$BaseApk      = "apk\base.apk",
    [string]$SplitApk     = "apk\split_arm64.apk",
    [string]$CnZip        = "assets\lwlocal.zip",
    [string]$Icon         = "assets\tlw_icon.png",
    [string]$OldActivity  = "com.google.firebase.MessagingUnityPlayerActivity",
    [string]$SetupActivity = "tlw.cn.CnSetupActivity",
    [string]$Authority    = "tlw.fps.cn",
    [string]$CnVersion    = "v1.3-20261109b+ci1",
    # Toolchain overrides (auto-detected when empty). Lets the folder be moved to
    # another machine without editing this script.
    [string]$JdkHome      = "",
    [string]$SdkRoot      = "",
    [string]$PythonExe    = "",
    [string]$KeyStore     = "tlw-release.jks",
    [string]$KeyAlias     = "tlw",
    [string]$R8Jar        = "r8.jar",
    [switch]$KeepIntermediate
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# ------------------------------------------------------------------ toolchain
function Find-FirstExisting($candidates) {
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    return $null
}

if (-not $JdkHome) {
    $JdkHome = Find-FirstExisting @(
        $env:JAVA_HOME,
        "D:\Android\Android Studio\jbr",
        "$env:LOCALAPPDATA\Programs\Android Studio\jbr",
        "C:\Program Files\Android\Android Studio\jbr"
    )
    if (-not $JdkHome) {
        $javacCmd = Get-Command javac.exe -ErrorAction SilentlyContinue
        if ($javacCmd) { $JdkHome = Split-Path -Parent (Split-Path -Parent $javacCmd.Source) }
    }
}
if (-not $JdkHome -or -not (Test-Path (Join-Path $JdkHome "bin\javac.exe"))) {
    throw "JDK not found. Pass -JdkHome <JDK/JBR dir> or set JAVA_HOME."
}
$java  = Join-Path $JdkHome "bin\java.exe"
$javac = Join-Path $JdkHome "bin\javac.exe"

if (-not $SdkRoot) {
    $SdkRoot = Find-FirstExisting @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        "D:\Android\SDK",
        "$env:LOCALAPPDATA\Android\Sdk"
    )
}
if (-not $SdkRoot) { throw "Android SDK not found. Pass -SdkRoot <SDK dir> or set ANDROID_SDK_ROOT." }

# newest build-tools that has zipalign/apksigner/aapt2
$btCandidates = Get-ChildItem (Join-Path $SdkRoot "build-tools") -Directory -ErrorAction SilentlyContinue |
    Where-Object {
        (Test-Path (Join-Path $_.FullName "zipalign.exe")) -and
        (Test-Path (Join-Path $_.FullName "apksigner.bat")) -and
        (Test-Path (Join-Path $_.FullName "aapt2.exe"))
    } |
    Sort-Object { try { [version]($_.Name -replace '-.*$', '') } catch { [version]"0.0" } } -Descending
if (-not $btCandidates) { throw "no usable build-tools under $SdkRoot\build-tools" }
$bt = $btCandidates[0].FullName

# newest platform android.jar (API 30+)
$platCandidates = Get-ChildItem (Join-Path $SdkRoot "platforms") -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "android.jar") } |
    Sort-Object { try { [int](($_.Name -replace '^android-', '') -replace '\..*$', '') } catch { 0 } } -Descending
if (-not $platCandidates) { throw "no android.jar under $SdkRoot\platforms" }
$androidJar = Join-Path $platCandidates[0].FullName "android.jar"

# python: python.exe preferred, otherwise the py launcher with -3
$pythonPrefix = @()
if ($PythonExe) {
    $pythonCmd = $PythonExe
} else {
    $pyCmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $pythonCmd = $pyCmd.Source
    } else {
        $pyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
        if (-not $pyLauncher) { throw "Python 3 not found. Pass -PythonExe <python.exe>." }
        $pythonCmd = $pyLauncher.Source
        $pythonPrefix = @('-3')
    }
}
function Py { & $pythonCmd @pythonPrefix @args }

$r8         = $R8Jar
$ks         = $KeyStore
$pass       = $env:TLW_KEYSTORE_PASSWORD
if (-not $pass) { throw "Set TLW_KEYSTORE_PASSWORD before building." }

$sw = [Diagnostics.Stopwatch]::StartNew()
function Step($n, $msg) { Write-Host "[$n/7] $msg" -ForegroundColor Cyan }

foreach ($p in @($java, $javac, $androidJar, $r8, $ks,
                 (Join-Path $bt "zipalign.exe"), (Join-Path $bt "apksigner.bat"),
                 (Join-Path $bt "aapt2.exe"))) {
    if (-not (Test-Path $p)) { throw "missing required tool: $p" }
}
if (-not (Test-Path $CnZip)) { throw "CN data zip not found: $CnZip" }
Write-Host "      JDK        : $JdkHome"
Write-Host "      SDK        : $SdkRoot"
Write-Host "      build-tools: $(Split-Path -Leaf $bt)"
Write-Host "      android.jar: $(Split-Path -Leaf (Split-Path -Parent $androidJar))"
Write-Host "      python     : $pythonCmd $($pythonPrefix -join ' ')"

# Release version marker. The lwlocal.zip shipped by the CN patch project still contains a
# stale internal lwlocal/version.txt (v1.3 -> v1.1-20261108), so the installer prefers this
# asset for both the "already installed" marker and the version shown in the UI.
$verFile = "build\tlw_cn.version"
New-Item -ItemType Directory -Force -Path "build" | Out-Null
[System.IO.File]::WriteAllText((Join-Path $root $verFile), $CnVersion + "`n",
    (New-Object System.Text.UTF8Encoding($false)))
Write-Host "      CN version: $CnVersion -> assets/tlw_cn.version"

Step 1 "javac (src\tlw\fps + src\tlw\cn)"
Remove-Item -Recurse -Force "build\classes", "build\dexout" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "build\classes", "build\dexout" | Out-Null
$srcs = @((Get-ChildItem "src\tlw\fps\*.java").FullName)
$cnSrc = Get-ChildItem "src\tlw\cn\*.java" -ErrorAction SilentlyContinue
if ($cnSrc) {
    $srcs += $cnSrc.FullName
    Write-Host "      cn sources: $($cnSrc.Count) file(s)"
} else {
    Write-Host "      WARNING: src\tlw\cn\*.java missing -> using build\stub (pipeline test only)" -ForegroundColor DarkYellow
    $srcs += (Get-ChildItem "build\stub\*.java").FullName
}
& $javac -source 8 -target 8 -g:none -nowarn -Xlint:-options -encoding UTF-8 `
    -bootclasspath $androidJar -d "build\classes" @srcs
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
Write-Host "      classes: $((Get-ChildItem build\classes -Recurse -Filter *.class).Count)"

Step 2 "d8 -> classes3.dex"
$classes = (Get-ChildItem "build\classes" -Recurse -Filter *.class).FullName
& $java -cp $r8 com.android.tools.r8.D8 --release --min-api 24 --lib $androidJar `
    --output "build\dexout" @classes
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }
Write-Host "      dex: $((Get-Item 'build\dexout\classes.dex').Length) bytes"

Step 3 "AndroidManifest.xml (binary AXML edits)"
$manifestFrom = "build\AndroidManifest.orig.xml"
Py -c 'import zipfile,sys;open(sys.argv[2],"wb").write(zipfile.ZipFile(sys.argv[1]).read("AndroidManifest.xml"))' $BaseApk $manifestFrom
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $manifestFrom)) { throw "cannot read AndroidManifest.xml from $BaseApk" }

$m0 = $manifestFrom
Py "tools\axml.py" add-provider $m0 "build\AndroidManifest.p.xml" "tlw.fps.TlwBoot" $Authority
if ($LASTEXITCODE -ne 0) { throw "provider injection failed" }
Py "tools\axml.py" add-perm "build\AndroidManifest.p.xml" "build\AndroidManifest.q.xml" android.permission.SYSTEM_ALERT_WINDOW
if ($LASTEXITCODE -ne 0) { throw "permission add failed" }
Py "tools\axml.py" drop-attr "build\AndroidManifest.q.xml" "build\AndroidManifest.s.xml" manifest requiredSplitTypes manifest splitTypes
if ($LASTEXITCODE -ne 0) { throw "split-attr drop failed" }
$hw = Py "tools\axml.py" set-bool "build\AndroidManifest.s.xml" "build\AndroidManifest.h.xml" "activity@android:name=$OldActivity" hardwareAccelerated true 2>&1
$hw | ForEach-Object { Write-Host "      $_" }
if ($LASTEXITCODE -ne 0) { throw "hw-accel patch failed" }
if (($hw -join "`n") -notmatch "total changed: 1") {
    throw "hardwareAccelerated did not land on '$OldActivity' -- check the launcher activity name (aapt2 dump badging)"
}
Py "tools\axml.py" set-launcher "build\AndroidManifest.h.xml" "build\AndroidManifest.xml" $OldActivity $SetupActivity
if ($LASTEXITCODE -ne 0) { throw "launcher switch failed" }
Write-Host "      manifest: $((Get-Item 'build\AndroidManifest.xml').Length) bytes"

Step 4 "repack (base + split libs + manifest + dex + icon + lwlocal.zip)"
Remove-Item "build\unaligned.apk" -ErrorAction SilentlyContinue
Py "tools\repack.py" $BaseApk $SplitApk "build\AndroidManifest.xml" `
    "build\dexout\classes.dex" "build\unaligned.apk" $Icon `
    -asset-store "assets/lwlocal.zip=$CnZip" `
    -asset "assets/tlw_cn.version=$verFile"
if ($LASTEXITCODE -ne 0) { throw "repack failed" }
$mb = [math]::Round((Get-Item "build\unaligned.apk").Length / 1MB, 1)
Write-Host "      unaligned: $mb MB"

Step 5 "zipalign -p -f 4"
Remove-Item "build\aligned.apk" -ErrorAction SilentlyContinue
& (Join-Path $bt "zipalign.exe") -p -f 4 "build\unaligned.apk" "build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }
if (-not $KeepIntermediate) { Remove-Item "build\unaligned.apk" -ErrorAction SilentlyContinue }

Step 6 "apksigner (v1+v2+v3)"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
Remove-Item $Out -ErrorAction SilentlyContinue
& (Join-Path $bt "apksigner.bat") sign --ks $ks --ks-pass env:TLW_KEYSTORE_PASSWORD --key-pass env:TLW_KEYSTORE_PASSWORD `
    --ks-key-alias $KeyAlias --v1-signing-enabled true --v2-signing-enabled true `
    --v3-signing-enabled true --out $Out "build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }
if (-not $KeepIntermediate) { Remove-Item "build\aligned.apk" -ErrorAction SilentlyContinue }

Step 7 "verify"
& (Join-Path $bt "apksigner.bat") verify --print-certs $Out | Select-Object -First 2 | ForEach-Object { Write-Host "      $_" }
$aapt = Join-Path $bt "aapt2.exe"
& $aapt dump badging $Out 2>&1 | Select-String "^package:|^application-label:|^launchable-activity:|^native-code:|^sdkVersion|^targetSdkVersion" |
    ForEach-Object { Write-Host "      $($_.Line)" }

$mb = [math]::Round((Get-Item $Out).Length / 1MB, 1)
$sw.Stop()
Write-Host ""
Write-Host "OK -> $Out ($mb MB, $([math]::Round($sw.Elapsed.TotalSeconds,1)) s)" -ForegroundColor Green
