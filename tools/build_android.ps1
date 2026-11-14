param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [int]$BuildNumber = 1,

    # Directory receiving the renamed per-ABI APKs. Defaults to
    # build\release_stage\v<Version> so releases can collect assets there.
    [string]$StageDir = ""
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FlutterExe = 'C:\dev\flutter-arm64\bin\flutter.bat'
$AppCnName = [string]::new([char[]]@(0x56FE,0x5B66,0x57FA,0x7840,0x6559,0x7A0B,0x4E60,0x9898,0x89E3,0x7B54))

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version format '$Version'. Expected semantic version like 0.1.3"
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Set-Location $ProjectRoot

# 1. Sync pubspec.yaml version (same contract as build_package.ps1)
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$PubspecText = [System.IO.File]::ReadAllText($PubspecPath, $Utf8NoBom)
$PubspecText = [regex]::Replace($PubspecText, '(?m)^version:\s*.*$', "version: $Version+$BuildNumber", 1)
[System.IO.File]::WriteAllText($PubspecPath, $PubspecText, $Utf8NoBom)
Write-Host "Updated pubspec.yaml to $Version+$BuildNumber"

# 2. Build per-ABI release APKs (no universal APK by design)
& $FlutterExe build apk --release --split-per-abi --build-name=$Version --build-number=$BuildNumber
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

$ApkDir = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk'
$ApkMap = @{
    'app-arm64-v8a-release.apk'     = "$AppCnName-Android-arm64-v8a-$Version.apk"
    'app-armeabi-v7a-release.apk'   = "$AppCnName-Android-armeabi-v7a-$Version.apk"
    'app-x86_64-release.apk'        = "$AppCnName-Android-x86_64-$Version.apk"
}

if ($StageDir -eq '') {
    $StageDir = Join-Path $ProjectRoot "build\release_stage\v$Version"
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

foreach ($entry in $ApkMap.GetEnumerator()) {
    $src = Join-Path $ApkDir $entry.Key
    if (-not (Test-Path $src)) {
        throw "Expected APK not found: $src"
    }
    $dst = Join-Path $StageDir $entry.Value
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "Staged $($entry.Value) ($('{0:N2}' -f ((Get-Item $dst).Length / 1MB)) MB)"
}

Write-Host "Android release assets ready in: $StageDir"