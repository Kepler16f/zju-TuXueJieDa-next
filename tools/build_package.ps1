param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [int]$BuildNumber = 1,

    [ValidateSet('Windows-arm64', 'Windows-x64', 'Windows-x86', 'Windows-arm32')]
    [string]$Target = 'Windows-arm64',

    [switch]$SkipFlutterBuild,

    [string]$DownloadsDir = "$env:USERPROFILE\Downloads"
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FlutterExe = 'C:\dev\flutter-arm64\bin\flutter.bat'
$IsccExe = 'C:\dev\tools\InnoSetup6\ISCC.exe'
$AppCnName = [string]::new([char[]]@(0x56FE,0x5B66,0x57FA,0x7840,0x6559,0x7A0B,0x4E60,0x9898,0x89E3,0x7B54))

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version format '$Version'. Expected semantic version like 0.0.1"
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)

Set-Location $ProjectRoot

# 1. Ensure installer.iss has UTF-8 BOM for Inno Setup Unicode handling
$IssPath = Join-Path $ProjectRoot 'tools\installer.iss'
$IssText = [System.IO.File]::ReadAllText($IssPath, $Utf8NoBom)
[System.IO.File]::WriteAllText($IssPath, $IssText, $Utf8Bom)

# 2. Sync pubspec.yaml version (clean UTF-8 without BOM)
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$PubspecText = [System.IO.File]::ReadAllText($PubspecPath, $Utf8NoBom)
$PubspecText = [regex]::Replace($PubspecText, '(?m)^version:\s*.*$', "version: $Version+$BuildNumber", 1)
[System.IO.File]::WriteAllText($PubspecPath, $PubspecText, $Utf8NoBom)
Write-Host "Updated pubspec.yaml to $Version+$BuildNumber"

# 3. Build Windows release output
if (-not $SkipFlutterBuild) {
    & $FlutterExe pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    & $FlutterExe build windows --release --build-name=$Version --build-number=$BuildNumber
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
}

$ArchMap = @{
    'Windows-arm64' = @{ Sub = 'arm64'; Allowed = 'arm64'; Mode64 = 'arm64' }
    'Windows-x64'   = @{ Sub = 'x64';   Allowed = 'x64compatible'; Mode64 = 'x64compatible' }
    'Windows-x86'   = @{ Sub = 'x86';   Allowed = 'x86'; Mode64 = '' }
    'Windows-arm32' = @{ Sub = 'arm';   Allowed = ''; Mode64 = '' }
}
$ArchCfg = $ArchMap[$Target]
$ReleaseDir = Join-Path $ProjectRoot "build\windows\$($ArchCfg.Sub)\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    throw "Build output directory not found at $ReleaseDir"
}

# 4. Clean old packages of this app in Downloads
if (-not (Test-Path $DownloadsDir)) {
    New-Item -ItemType Directory -Path $DownloadsDir -Force | Out-Null
}
foreach ($pattern in @("$AppCnName*", 'zju-TuXueJieDa-next-*')) {
    Get-ChildItem -Path $DownloadsDir -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Cleaning old package: $($_.FullName)"
        Remove-Item -Path $_.FullName -Recurse -Force
    }
}

# 5. Build native Setup EXE with Inno Setup (fallback to zip if ISCC unavailable)
$IconPath = Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico'
$BaseName = "$AppCnName-$Target-$Version-setup"

if (Test-Path $IsccExe) {
    $IsccArgs = @(
        "/DMyAppVersion=$Version",
        "/DMyAppName=$AppCnName",
        "/DMyAllowedArch=$($ArchCfg.Allowed)",
        "/DMyInstall64BitMode=$($ArchCfg.Mode64)",
        "/DMySourceDir=$ReleaseDir",
        "/DMyOutputDir=$DownloadsDir",
        "/DMyOutputBaseFilename=$BaseName",
        "/DMyIconPath=$IconPath",
        $IssPath
    )
    & $IsccExe @IsccArgs
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup ISCC failed with code $LASTEXITCODE" }
    $OutExe = Join-Path $DownloadsDir "$BaseName.exe"
    Write-Host "Packaged installer successfully: $OutExe ($('{0:N2}' -f ((Get-Item $OutExe).Length / 1MB)) MB)"
} else {
    throw "ISCC.exe not found at $IsccExe"
}
