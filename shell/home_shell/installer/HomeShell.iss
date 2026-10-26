; Home Shell installer (Inno Setup 6). Per-user: no admin rights, nothing in system folders.
; Build:  flutter build windows --release   then compile this file with Inno Setup.
#define AppName "Home Shell"
#define AppExe "home_shell.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6F3B1D0C-4E5A-4C8B-9A71-HOMESHELL0001}
AppName={#AppName}
AppVersion=0.1.0
DefaultDirName={localappdata}\HomeShell
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=HomeShell-Setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Registry]
; Same startup entry the app uses itself; removed on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "HomeShell"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "Start Home Shell now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "KillHomeShell"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    if MsgBox('Also delete your saved bar items and settings?', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DelTree(ExpandConstant('{userappdata}\HomeShell'), True, True, True);
end;
