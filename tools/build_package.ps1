param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [int]$BuildNumber = 1,

    [ValidateSet('windows-arm64', 'windows-x64')]
    [string]$Target = 'windows-arm64',

    [string]$DownloadsDir = "$env:USERPROFILE\Downloads"
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FlutterExe = 'C:\dev\flutter-arm64\bin\flutter.bat'

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version format '$Version'. Expected semantic version like 0.0.1"
}

Set-Location $ProjectRoot

# 1. Sync pubspec.yaml version
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$PubspecText = Get-Content $PubspecPath -Raw -Encoding UTF8
$PubspecText = [regex]::Replace($PubspecText, '(?m)^version:\s*.*$', "version: $Version+$BuildNumber", 1)
Set-Content -Path $PubspecPath -Value $PubspecText -Encoding UTF8 -NoNewline
Write-Host "Updated pubspec.yaml to $Version+$BuildNumber"

# 2. Fetch packages & build Windows release
& $FlutterExe pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

& $FlutterExe build windows --release --build-name=$Version --build-number=$BuildNumber
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

# Locate runner output folder (Flutter arm64 places it under build\windows\arm64\runner\Release or x64\runner\Release)
$ArchSub = if ($Target -eq 'windows-arm64') { 'arm64' } else { 'x64' }
$ReleaseDir = Join-Path $ProjectRoot "build\windows\$ArchSub\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    throw "Build output directory not found at $ReleaseDir"
}

# 3. Clean old zju-TuXueJieDa-next packages in Downloads
if (-not (Test-Path $DownloadsDir)) {
    New-Item -ItemType Directory -Path $DownloadsDir -Force | Out-Null
}
Get-ChildItem -Path $DownloadsDir -Filter 'zju-TuXueJieDa-next-*' -File | ForEach-Object {
    Write-Host "Cleaning old package: $($_.FullName)"
    Remove-Item -Path $_.FullName -Force
}

# 4. Stage & compress new release package (portable zip)
$StageRoot = Join-Path $ProjectRoot "build\package_stage"
$StageAppDir = Join-Path $StageRoot "zju-TuXueJieDa-next-v$Version-$Target"
if (Test-Path $StageRoot) {
    Remove-Item -Path $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $StageAppDir -Force | Out-Null
Copy-Item -Path (Join-Path $ReleaseDir '*') -Destination $StageAppDir -Recurse -Force

$ZipName = "zju-TuXueJieDa-next-v$Version-$Target.zip"
$OutZip = Join-Path $DownloadsDir $ZipName
Compress-Archive -Path $StageAppDir -DestinationPath $OutZip -CompressionLevel Optimal -Force

Write-Host "Packaged successfully: $OutZip ($('{0:N2}' -f ((Get-Item $OutZip).Length / 1MB)) MB)"
