#define AppVersion GetEnv("MEGAWATCH_VERSION")
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{5E1D7C42-3B8A-4F6E-9A0D-7C2B91E4A6D3}}
AppName=MegaWatch
AppVersion={#AppVersion}
AppPublisher=MegaWatch (based on Debrify)
AppPublisherURL=https://github.com/varunsalian/debrify
DefaultDirName={autopf}\\MegaWatch
DisableDirPage=yes
DefaultGroupName=MegaWatch
DisableProgramGroupPage=yes
OutputDir=..\\build\\windows\\installer
OutputBaseFilename=megawatch-{#AppVersion}-setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=runner\\resources\\app_icon.ico
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\\build\\windows\\x64\\runner\\Release\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\MegaWatch"; Filename: "{app}\\debrify.exe"
Name: "{autodesktop}\\MegaWatch"; Filename: "{app}\\debrify.exe"; Tasks: desktopicon

[Registry]
; Register stremio:// URL protocol
Root: HKCU; Subkey: "Software\\Classes\\stremio"; ValueType: string; ValueData: "URL:Stremio Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\stremio"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\stremio\\shell\\open\\command"; ValueType: string; ValueData: """{app}\\debrify.exe"" ""%1"""

; Register debrify:// URL protocol (OAuth callbacks, etc.)
Root: HKCU; Subkey: "Software\\Classes\\debrify"; ValueType: string; ValueData: "URL:Debrify Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\debrify"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\debrify\\shell\\open\\command"; ValueType: string; ValueData: """{app}\\debrify.exe"" ""%1"""

[Run]
Filename: "{app}\\debrify.exe"; Description: "Launch MegaWatch"; Flags: nowait postinstall skipifsilent
