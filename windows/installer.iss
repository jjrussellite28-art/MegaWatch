#define AppVersion GetEnv("MEGAWATCH_VERSION")
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{9B23C6A1-6A05-4B0C-9D6C-5DB02E2AA8F7}}
AppName=MegaWatch
AppVersion={#AppVersion}
AppPublisher=MegaWatch
AppPublisherURL=https://github.com/jjrussellite28-art/MegaWatch
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
Name: "{group}\\MegaWatch"; Filename: "{app}\\megawatch.exe"
Name: "{autodesktop}\\MegaWatch"; Filename: "{app}\\megawatch.exe"; Tasks: desktopicon

[Registry]
; Register stremio:// URL protocol
Root: HKCU; Subkey: "Software\\Classes\\stremio"; ValueType: string; ValueData: "URL:Stremio Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\stremio"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\stremio\\shell\\open\\command"; ValueType: string; ValueData: """{app}\\megawatch.exe"" ""%1"""

; Register magnet:// URL protocol
Root: HKCU; Subkey: "Software\\Classes\\magnet"; ValueType: string; ValueData: "URL:Magnet Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\magnet"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\magnet\\shell\\open\\command"; ValueType: string; ValueData: """{app}\\megawatch.exe"" ""%1"""

; Register megawatch:// URL protocol (OAuth callbacks, etc.)
Root: HKCU; Subkey: "Software\\Classes\\megawatch"; ValueType: string; ValueData: "URL:MegaWatch Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\megawatch"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\megawatch\\shell\\open\\command"; ValueType: string; ValueData: """{app}\\megawatch.exe"" ""%1"""

[Run]
Filename: "{app}\\megawatch.exe"; Description: "Launch MegaWatch"; Flags: nowait postinstall skipifsilent
