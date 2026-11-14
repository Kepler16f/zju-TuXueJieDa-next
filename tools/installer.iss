#ifndef MyAppVersion
  #define MyAppVersion "0.0.1"
#endif
#ifndef MyAppName
  #define MyAppName "图学基础教程习题解答"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "tuxuejieda_next.exe"
#endif
#ifndef MyAllowedArch
  #define MyAllowedArch "arm64"
#endif
#ifndef MyInstall64BitMode
  #define MyInstall64BitMode "arm64"
#endif
#ifndef MySourceDir
  #define MySourceDir "..\build\windows\arm64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\build\package_stage"
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "图学基础教程习题解答-Windows-arm64-0.0.1-setup"
#endif
#ifndef MyIconPath
  #define MyIconPath "..\windows\runner\resources\app_icon.ico"
#endif

[Setup]
AppId={{8F6C8A5C-4D3E-4C7A-9F2B-1A2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Kepler16f
AppPublisherURL=https://github.com/Kepler16f/zju-TuXueJieDa-next
AppSupportURL=https://github.com/Kepler16f/zju-TuXueJieDa-next/issues
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
#if MyAllowedArch != ""
ArchitecturesAllowed={#MyAllowedArch}
#endif
#if MyInstall64BitMode != ""
ArchitecturesInstallIn64BitMode={#MyInstall64BitMode}
#endif
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
SetupIconFile={#MyIconPath}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 步骤图自 v0.1.3 起为 WebP；清理旧版本遗留的 PNG（Inno 不删除多余文件）。
[InstallDelete]
Type: files; Name: "{app}\data\flutter_assets\assets\steps\*.png"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
