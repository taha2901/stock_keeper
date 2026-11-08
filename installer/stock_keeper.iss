; Inno Setup script for the Windows desktop installer.
; Do not compile this directly: run installer\build_installer.ps1, which builds
; the app, gathers the VC++ runtime and passes in the version from pubspec.yaml.
;
; This file must stay UTF-8 WITH BOM, or the Arabic text below gets corrupted.

#ifndef AppVersion
  #error Run installer\build_installer.ps1 instead of compiling this file directly.
#endif

#define AppName "المستودع"
#define AppPublisher "com.sanunited"
#define AppExe "stock_keeper.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId identifies the app for upgrades. Never change it, or a new version
; installs beside the old one instead of replacing it.
AppId={{7E4B1C52-9A3D-4F68-B0E7-2D5C8A916F34}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}

; Per-user install: no admin prompt, goes to %LOCALAPPDATA%\Programs.
PrivilegesRequired=lowest
DefaultDirName={autopf}\StockKeeper
DefaultGroupName={#AppName}

; Store-like flow: no wizard questions, just install and open.
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
ShowLanguageDialog=no
WizardStyle=modern

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; Closes a running copy during an upgrade so its files can be replaced.
CloseApplications=force
RestartApplications=no

SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

OutputDir=..\build\installer
OutputBaseFilename=StockKeeper-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; VC++ runtime next to the exe, so a clean PC needs no separate download.
Source: "..\build\installer\vcruntime\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; User data lives in %APPDATA%\com.sanunited\stock_keeper and is deliberately
; left in place on uninstall, so reinstalling keeps the stock records.
